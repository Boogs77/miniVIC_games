;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;                                                              ;
;   THE WARRIORS - 1 vs 1 fighting game (Street Fighter style) ;
;   65C02 assembly, TMS9918A Graphics II                       ;
;   Base: 1vs1 basket (NMI/vblank + SAT buffer, VDP, joystick) ;
;                                                              ;
;   - P1 on PORTA $D581, P2 on PORTB $D580                     ;
;   - joystick: left/right = walk, UP = jump                   ;
;       hold BACK (away from opponent) = block                 ;
;   - button 1 = PUNCH, button 2 = KICK                        ;
;     both buttons together = SPECIAL MOVE (bar must be full)  ;
;   - 5 warriors: MATTIA DAVIDE THOMAS NICHOLAS ELIA           ;
;   - 6 stages, best of 3 rounds                               ;
;   - graphics (6 stages, title, select, sprites) are in the   ;
;     tables at the bottom (generated, RLE compressed)         ;
;   - fighters: magnified sprites (32x64), skin-coloured top,  ;
;     legs in the warrior colour, black layer for the outline  ;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

VDP_INIT                 = $30
VDP_INIT_HI              = $31

; per-player data: 2 bytes each, index X = 0 (P1) / 1 (P2)
P_CX                     = $60     ; X of the body centre
P_ST                     = $62     ; state
P_FACE                   = $64     ; 0 = right, 1 = left
P_JOY                    = $66
P_OLD                    = $68
P_EDGE                   = $6A
P_WALK                   = $6C
P_JUMP                   = $6E     ; jump frames left (0 = on ground)
P_VX                     = $70     ; horizontal speed (signed)
P_TMR                    = $72
P_ATK                    = $74     ; 0 none, 1 punch, 2 kick, 3 special
P_HITD                   = $76     ; this attack already hit
P_HP                     = $78
P_SP                     = $7A     ; special meter
P_BUF                    = $7C     ; button buffer timer
P_BTN                    = $7E     ; buffered buttons
P_CHAR                   = $80
P_WINS                   = $82
P_BLK                    = $84     ; last hit was blocked
P_LOCK                   = $86     ; select screen: character locked
PR_ON                    = $88     ; projectiles
PR_X                     = $8A
PR_DIR                   = $8C
SPK_T                    = $8E
SPK_X                    = $8F
SPK_Y                    = $90
RND                      = $91
PHASE                    = $92
PH_TMR                   = $93
ROUND                    = $94
TIME_SEC                 = $95
TIME_FR                  = $96
WINNER                   = $97
STAGE                    = $98
BARS_D                   = $99
NT_DIRTY                 = $9A
INT_FLAG                 = $9B
ARMED                    = $9C
GO_DELAY                 = $9D
SCN                      = $9E
MSG_TMR                  = $9F
STG_OLD                  = $A0
SEL_CNT                  = $A1
FRAME_CNT                = $A2
LAST_FRAME               = $A3
T0                       = $A4
T1                       = $A5
T2                       = $A6
T3                       = $A7
T4                       = $A8
T5                       = $A9
T6                       = $AA
T7                       = $AB
PTR                      = $AC     ; 2 bytes
VP                       = $B0     ; music voice pointers (3 x 2)
N0                       = $B6
MAG                      = $B7     ; 1 = magnified sprites (always on)
VCNT                     = $B8

; sound state (RAM)
MUS_ON                   = $0300
MUS_REQ                  = $0301
SFX_REQ                  = $0302
SFX_ON                   = $0303
SFX_TL                   = $0304
SFX_TH                   = $0305
SFX_SL                   = $0306
SFX_NZ                   = $0307
SFX_TV                   = $0308
SFX_NV                   = $0309
SFX_FL                   = $030A
MUS_S6                   = $030B
MUS_ENDED                = $030C
VT                       = $0310
VVOL                     = $0316
VDC                      = $031C
VPL                      = $0322
VPH                      = $0328
VEND                     = $032E

; AY-3-8910 (stereo pair, 1 MHz clock): right and left
AYR_LATCH                = $D380
AYR_WRITE                = $D381
AYL_LATCH                = $D384
AYL_WRITE                = $D385

NT_BUF                   = $0200   ; name table rows 0-2 (96 bytes), copied by the NMI
SAT_BUFFER               = $0260   ; 7 sprites + 4 outline sprites + 2 select arrows + terminator (53 bytes)

PORTB_JOY = $d580
PORTA_JOY = $d581
DDRB_JOY  = $d582
DDRA_JOY  = $d583

; ---------------- game parameters ----------------
GROUND_Y      = 170
XMINC         = 16
XMAXC         = 240
MINSEP        = 22
JUMP_LEN      = 32
VTOL          = 30
SKIN_COL      = $09     ; torso colour of every fighter
HP_MAX        = 96
SP_MAX        = 64
SPEC_WIN      = 3
HIDE_Y        = $C0
BTN_MASK      = %00110000

ST_IDLE       = 0
ST_JUMP       = 1
ST_PUNCH      = 2
ST_KICK       = 3
ST_SPEC       = 4
ST_HIT        = 5
ST_KO         = 6
ST_WIN        = 7

PH_INTRO      = 0
PH_FIGHT      = 1
PH_KO         = 2

T_IDLE        = 0
T_PUNCH       = 1
T_KICK        = 2
T_JUMP        = 3
T_HIT         = 4
T_BLOCK       = 5
T_SPEC        = 6
B_A           = 0
B_B           = 1
B_JUMP        = 2
B_KICK        = 3

MSG_FIGHT     = 4
MSG_KO        = 5
MSG_TIMEUP    = 6
MSG_DRAW      = 7

TILE_MARK     = $9B

 .org $0FD0
DISPATCH:
  JMP NMI_TASK

 .org $1000
VREG  = $B001
VDATA = $B000

VDP_NAME_TABLE_BASE    = $3800
VDP_SPRITE_ATT_BASE    = $3B00
VDP_WRITE_VRAM_BIT     = %01000000
VDP_REGISTER_BITS      = %10000000

RESET:
  JSR VDP_SET_REGISTERS
  JSR CLEAR_VRAM
  LDA #$00
  STA DDRA_JOY
  STA DDRB_JOY
  LDX #$60
.rs_z:
  STA $00,X
  INX
  CPX #$C0
  BNE .rs_z
  LDX #$00
.rs_z2:
  STA $0300,X
  INX
  BNE .rs_z2
  LDA #$A5
  STA RND
  LDA #1                        ; sprites are always magnified
  STA MAG
  LDA #$D0
  STA SAT_BUFFER+52
  JSR HIDE_SPRITES
  JSR AY_INIT
  ; sprite patterns -> VRAM $1800
  LDA #$00
  STA VREG
  LDA #$58
  STA VREG
  LDA #<SPR_DATA
  STA PTR
  LDA #>SPR_DATA
  STA PTR+1
  LDA #<(SPR_END-SPR_DATA)
  STA T0
  LDA #>(SPR_END-SPR_DATA)
  STA T1
  JSR VCOPY
  JMP TITLE

; ===============================================================
TITLE:
  LDX #$FF
  TXS
  JSR HIDE_SPRITES
  LDA #0
  JSR LOAD_SCENE
  LDA #<TITLE_REC
  STA PTR
  LDA #>TITLE_REC
  STA PTR+1
  JSR DRAW_RECORDS
  JSR VDP_INT_ON
  LDA #1                        ; intro music
  JSR MUS_PLAY
  JSR WAIT_FIRE
  LDA FRAME_CNT
  ORA #$01
  STA RND
  JMP SELECT

; ===============================================================
;  CHARACTER SELECT
; ===============================================================
SELECT:
  LDX #$FF
  TXS
  JSR HIDE_SPRITES
  LDA #1
  JSR LOAD_SCENE
  LDA #<SEL_REC
  STA PTR
  LDA #>SEL_REC
  STA PTR+1
  JSR DRAW_RECORDS
  JSR VDP_INT_ON
  LDA #0
  STA P_LOCK
  STA P_LOCK+1
  STA P_ST
  STA P_ST+1
  STA P_JUMP
  STA P_JUMP+1
  STA P_WALK
  STA P_WALK+1
  STA P_BLK
  STA P_BLK+1
  STA P_CHAR
  STA P_FACE
  STA SEL_CNT
  LDA #4
  STA P_CHAR+1
  LDA #1
  STA P_FACE+1
  LDA #40
  STA P_CX
  LDA #216
  STA P_CX+1
  JSR READ_JOY
  LDA P_JOY
  STA P_OLD
  LDA P_JOY+1
  STA P_OLD+1
  JSR SEL_REFRESH
.sl_loop:
  JSR READ_JOY
  LDX #0
  JSR SEL_PLAYER
  LDX #1
  JSR SEL_PLAYER
  LDA P_LOCK
  AND P_LOCK+1
  BEQ .sl_nb
  INC SEL_CNT
  LDA SEL_CNT
  CMP #45
  BNE .sl_draw
  JMP STAGE_SELECT
.sl_nb:
  LDA #0
  STA SEL_CNT
.sl_draw:
  JSR SEL_DRAW
  JSR WAIT_FRAME
  JMP .sl_loop

SEL_PLAYER:
  LDA P_JOY,X
  STA T0
  LDA P_OLD,X
  EOR #$FF
  AND T0
  STA T1
  LDA T0
  STA P_OLD,X
  LDA P_LOCK,X
  BNE .sp_lk
  LDA T1
  AND #%00000001
  BEQ .sp_nu
  LDA P_CHAR,X
  BNE .sp_u1
  LDA #5
.sp_u1:
  SEC
  SBC #1
  STA P_CHAR,X
  JSR SEL_REFRESH
.sp_nu:
  LDA T1
  AND #%00000010
  BEQ .sp_nd
  LDA P_CHAR,X
  CLC
  ADC #1
  CMP #5
  BCC .sp_d1
  LDA #0
.sp_d1:
  STA P_CHAR,X
  JSR SEL_REFRESH
.sp_nd:
  LDA T1
  AND #BTN_MASK
  BEQ .sp_ret
  TXA
  EOR #$01
  TAY
  LDA P_LOCK,Y
  BEQ .sp_ok
  LDA P_CHAR,Y
  CMP P_CHAR,X
  BEQ .sp_ret
.sp_ok:
  LDA #1
  STA P_LOCK,X
  LDA #ST_WIN
  STA P_ST,X
  JSR SEL_REFRESH
.sp_ret:
  RTS
.sp_lk:
  LDA T1
  AND #%00100000
  BEQ .sp_ret
  LDA #0
  STA P_LOCK,X
  STA P_ST,X
  JSR SEL_REFRESH
  RTS

; names, specials and status into NT_BUF (keeps X, T0-T3)
SEL_REFRESH:
  PHX
  JSR NT_CLEAR
  JSR HUD_NAMES
  LDA P_CHAR                    ; special names, row 1
  ASL A
  ASL A
  ASL A
  ASL A
  TAX
  LDY #0
.sr_a:
  LDA SPECL,X
  STA NT_BUF+32+1,Y
  INX
  INY
  CPY #12
  BNE .sr_a
  LDA P_CHAR+1
  ASL A
  ASL A
  ASL A
  ASL A
  TAX
  LDY #0
.sr_b:
  LDA SPECR,X
  STA NT_BUF+32+19,Y
  INX
  INY
  CPY #12
  BNE .sr_b
  LDA P_LOCK                    ; status, row 2
  ASL A
  ASL A
  ASL A
  TAX
  LDY #0
.sr_c:
  LDA STATT,X
  STA NT_BUF+64+1,Y
  INX
  INY
  CPY #8
  BNE .sr_c
  LDA P_LOCK+1
  ASL A
  ASL A
  ASL A
  CLC
  ADC #16
  TAX
  LDY #0
.sr_d:
  LDA STATT,X
  STA NT_BUF+64+23,Y
  INX
  INY
  CPY #8
  BNE .sr_d
  LDA #7
  STA NT_DIRTY
  PLX
  RTS

SEL_DRAW:
  LDX #0
  JSR DRAW_FIGHTER
  LDX #1
  JSR DRAW_FIGHTER
  LDX #0
.sd_c:
  TXA
  ASL A
  ASL A
  CLC
  ADC #44                       ; entries 11-12: they lose the 4-per-line limit, not the outlines
  TAY
  LDA P_CHAR,X
  ASL A
  CLC
  ADC #6
  ASL A
  ASL A
  ASL A
  SEC
  SBC #4
  STA SAT_BUFFER,Y
  CPX #0
  BNE .sd_p2
  LDA #78
  STA SAT_BUFFER+1,Y
  LDA #132
  STA SAT_BUFFER+2,Y
  BRA .sd_col
.sd_p2:
  LDA #166
  STA SAT_BUFFER+1,Y
  LDA #136
  STA SAT_BUFFER+2,Y
.sd_col:
  LDA P_CHAR,X
  STA T4
  STX T5
  LDX T4
  LDA SEL_COL,X
  STA SAT_BUFFER+3,Y
  LDX T5
  INX
  CPX #2
  BNE .sd_c
  LDA #HIDE_Y
  STA SAT_BUFFER+24
  RTS

; ===============================================================
;  STAGE SELECT (the stage is shown behind the text)
; ===============================================================
STAGE_SELECT:
  LDX #$FF
  TXS
  JSR HIDE_SPRITES
  LDA #0
  STA STAGE
  JSR READ_JOY
  LDA P_JOY
  ORA P_JOY+1
  STA STG_OLD
.ss_load:
  LDA STAGE
  CLC
  ADC #2
  JSR LOAD_SCENE
  JSR VDP_INT_ON
  JSR ST_TEXT
.ss_loop:
  JSR WAIT_FRAME
  JSR READ_JOY
  LDA P_JOY
  ORA P_JOY+1
  STA T0
  LDA STG_OLD
  EOR #$FF
  AND T0
  STA T1
  LDA T0
  STA STG_OLD
  LDA T1
  AND #BTN_MASK
  BEQ .ss_nb
  JMP FIGHT
.ss_nb:
  LDA T1
  AND #%00001000
  BEQ .ss_nr
  LDA STAGE
  CLC
  ADC #1
  CMP #6
  BCC .ss_r1
  LDA #0
.ss_r1:
  STA STAGE
  JMP .ss_load
.ss_nr:
  LDA T1
  AND #%00000100
  BEQ .ss_loop
  LDA STAGE
  BNE .ss_l1
  LDA #6
.ss_l1:
  SEC
  SBC #1
  STA STAGE
  JMP .ss_load

ST_TEXT:
  JSR NT_CLEAR
  LDA #<STG_HDR
  STA PTR
  LDA #>STG_HDR
  STA PTR+1
  LDX #10
  LDY #12
  JSR BUF_PUT
  LDA STAGE
  ASL A
  ASL A
  ASL A
  ASL A
  ASL A
  CLC
  ADC #<STGN
  STA PTR
  LDA #>STGN
  ADC #0
  STA PTR+1
  LDX #(32+6)
  LDY #20
  JSR BUF_PUT
  LDA #<STG_PRS
  STA PTR
  LDA #>STG_PRS
  STA PTR+1
  LDX #(64+9)
  LDY #14
  JSR BUF_PUT
  LDA #7
  STA NT_DIRTY
  RTS

; copies Y bytes from (PTR) to NT_BUF+X
BUF_PUT:
  STY T7
  LDY #0
.bp_l:
  LDA (PTR),Y
  STA NT_BUF,X
  INX
  INY
  CPY T7
  BNE .bp_l
  RTS

NT_CLEAR:
  LDX #95
  LDA #0
.nc_l:
  STA NT_BUF,X
  DEX
  BPL .nc_l
  RTS

; names of both players in row 0 of NT_BUF
HUD_NAMES:
  LDA P_CHAR
  ASL A
  ASL A
  ASL A
  TAX
  LDY #0
.hn_a:
  LDA NAMEL,X
  STA NT_BUF+1,Y
  INX
  INY
  CPY #8
  BNE .hn_a
  LDA P_CHAR+1
  ASL A
  ASL A
  ASL A
  TAX
  LDY #0
.hn_b:
  LDA NAMER,X
  STA NT_BUF+23,Y
  INX
  INY
  CPY #8
  BNE .hn_b
  RTS

; ===============================================================
;  FIGHT
; ===============================================================
FIGHT:
  LDA #0
  STA P_WINS
  STA P_WINS+1
  LDA #1
  STA ROUND
  JMP NEW_ROUND

NEW_ROUND:
  LDX #$FF
  TXS
  LDX #1
.nr_l:
  LDA #0
  STA P_ST,X
  STA P_JUMP,X
  STA P_VX,X
  STA P_TMR,X
  STA P_ATK,X
  STA P_HITD,X
  STA P_BUF,X
  STA P_BTN,X
  STA P_SP,X
  STA P_WALK,X
  STA P_OLD,X
  STA P_EDGE,X
  STA P_BLK,X
  STA PR_ON,X
  LDA #HP_MAX
  STA P_HP,X
  DEX
  BPL .nr_l
  LDA #72
  STA P_CX
  LDA #184
  STA P_CX+1
  LDA #0
  STA P_FACE
  STA SPK_T
  STA MSG_TMR
  STA WINNER
  LDA #1
  STA P_FACE+1
  LDA #60
  STA TIME_SEC
  STA TIME_FR
  LDA #76
  STA PH_TMR
  LDA #PH_INTRO
  STA PHASE
  JSR HUD_INIT
  LDA ROUND
  JSR SET_MSG
  LDA #2                        ; round jingle
  JSR MUS_PLAY
  JMP GAME_LOOP

GAME_LOOP:
  JSR READ_JOY
  LDA PHASE
  CMP #PH_FIGHT
  BEQ .gl_go
  LDA #0
  STA P_JOY
  STA P_JOY+1
.gl_go:
  LDX #0
  JSR UPDATE_FIGHTER
  LDX #1
  JSR UPDATE_FIGHTER
  LDX #0
  JSR UPDATE_PROJ
  LDX #1
  JSR UPDATE_PROJ
  JSR RESOLVE
  JSR UPDATE_PHASE
  LDA SPK_T
  BEQ .gl_nspk
  DEC SPK_T
.gl_nspk:
  JSR UPDATE_BARS
  JSR DRAW_ALL
  JSR WAIT_FRAME
  JMP GAME_LOOP

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

; ---------------------------------------------------------------
; HUD helpers (NT_BUF rows 0-2, copied to VRAM by the NMI)
; ---------------------------------------------------------------
HUD_INIT:
  JSR NT_CLEAR
  JSR HUD_NAMES
  LDA #$56
  STA NT_BUF+32+15
  LDA #$53
  STA NT_BUF+32+16
  LDA P_WINS
  BEQ .hi_a
  LDA #TILE_MARK
  STA NT_BUF+32+13
  LDA P_WINS
  CMP #2
  BCC .hi_a
  LDA #TILE_MARK
  STA NT_BUF+32+14
.hi_a:
  LDA P_WINS+1
  BEQ .hi_b
  LDA #TILE_MARK
  STA NT_BUF+32+18
  LDA P_WINS+1
  CMP #2
  BCC .hi_b
  LDA #TILE_MARK
  STA NT_BUF+32+17
.hi_b:
  LDA #1
  STA BARS_D
  JSR HUD_TIMER
  LDA #7
  STA NT_DIRTY
  RTS

HUD_TIMER:
  LDA TIME_SEC
  LDX #0
.ht_t:
  CMP #10
  BCC .ht_o
  SBC #10
  INX
  BRA .ht_t
.ht_o:
  CLC
  ADC #$30
  STA NT_BUF+16
  TXA
  CLC
  ADC #$30
  STA NT_BUF+15
  LDA NT_DIRTY
  ORA #1
  STA NT_DIRTY
  RTS

; A = message index (copied to the centre of row 2)
SET_MSG:
  ASL A
  ASL A
  ASL A
  ASL A
  TAX
  LDY #0
.sm_l:
  LDA MSGT,X
  STA NT_BUF+64+10,Y
  INX
  INY
  CPY #12
  BNE .sm_l
  LDA NT_DIRTY
  ORA #4
  STA NT_DIRTY
  LDA #0
  STA MSG_TMR
  RTS

; A = value, T2 = first tile, T3 = start index in NT_BUF, T4 = step, T5 = count
DRAW_BAR:
  STA T0
  LDX T3
.db_l:
  LDA T0
  CMP #8
  BCC .db_n
  LDA #8
.db_n:
  STA T1
  LDA T0
  SEC
  SBC T1
  STA T0
  LDA T1
  CLC
  ADC T2
  STA NT_BUF,X
  TXA
  CLC
  ADC T4
  TAX
  DEC T5
  BNE .db_l
  RTS

UPDATE_BARS:
  LDA BARS_D
  BEQ .ub_r
  LDA #0
  STA BARS_D
  LDA #$80
  STA T2
  LDA #(32+12)
  STA T3
  LDA #$FF
  STA T4
  LDA #12
  STA T5
  LDA P_HP
  JSR DRAW_BAR
  LDA #$89
  STA T2
  LDA #(32+19)
  STA T3
  LDA #$01
  STA T4
  LDA #12
  STA T5
  LDA P_HP+1
  JSR DRAW_BAR
  LDA #$92
  STA T2
  LDA #(64+1)
  STA T3
  LDA #$01
  STA T4
  LDA #8
  STA T5
  LDA P_SP
  JSR DRAW_BAR
  LDA #$92
  STA T2
  LDA #(64+23)
  STA T3
  LDA #$01
  STA T4
  LDA #8
  STA T5
  LDA P_SP+1
  JSR DRAW_BAR
  LDA NT_DIRTY
  ORA #6
  STA NT_DIRTY
.ub_r:
  RTS

; ---------------------------------------------------------------
;  round / match flow
; ---------------------------------------------------------------
UPDATE_PHASE:
  LDA MSG_TMR
  BEQ .up_nm
  DEC MSG_TMR
  BNE .up_nm
  LDA #0
  JSR SET_MSG
.up_nm:
  LDA PHASE
  BEQ .ph_intro
  CMP #PH_FIGHT
  BEQ .ph_fight
  ; ---- PH_KO
  DEC PH_TMR
  LDA PH_TMR
  CMP #70
  BNE .pk_a
  LDA WINNER
  BMI .pk_a
  TAX
  LDA #ST_WIN
  STA P_ST,X
  LDA #0
  STA P_VX,X
  STA P_ATK,X
.pk_a:
  LDA PH_TMR
  BNE .ph_ret
  JMP ROUND_OVER
.ph_intro:
  DEC PH_TMR
  BNE .ph_ret
  LDA #PH_FIGHT
  STA PHASE
  LDA #MSG_FIGHT
  JSR SET_MSG
  LDA #40
  STA MSG_TMR
  LDA #12
  JSR SFX_PLAY
.ph_ret:
  RTS
.ph_fight:
  LDA P_ST
  CMP #ST_KO
  BEQ .pf_ko
  LDA P_ST+1
  CMP #ST_KO
  BEQ .pf_ko
  DEC TIME_FR
  BNE .ph_ret
  LDA #60
  STA TIME_FR
  LDA TIME_SEC
  BEQ .ph_ret
  DEC TIME_SEC
  JSR HUD_TIMER
  LDA TIME_SEC
  BNE .ph_ret
  ; ---- time up: the higher energy wins
  LDA P_HP
  CMP P_HP+1
  BEQ .pf_tdraw
  BCS .pf_t0
  LDA #1
  STA WINNER
  LDX #0
  BRA .pf_tko
.pf_t0:
  LDA #0
  STA WINNER
  LDX #1
.pf_tko:
  LDA #ST_KO
  STA P_ST,X
  LDA #0
  STA P_BLK,X
  LDA #14
  STA P_JUMP,X
  LDA #MSG_TIMEUP
  BRA .pf_end
.pf_tdraw:
  LDA #$FF
  STA WINNER
  LDA #MSG_DRAW
  BRA .pf_end
.pf_ko:
  LDA P_ST
  CMP #ST_KO
  BNE .pf_w1
  LDA P_ST+1
  CMP #ST_KO
  BNE .pf_w1b
  LDA #$FF                      ; double KO
  STA WINNER
  LDA #MSG_DRAW
  BRA .pf_end
.pf_w1b:
  LDA #1
  STA WINNER
  BRA .pf_m
.pf_w1:
  LDA #0
  STA WINNER
.pf_m:
  LDA #MSG_KO
.pf_end:
  JSR SET_MSG
  LDA #PH_KO
  STA PHASE
  LDA #120
  STA PH_TMR
  RTS

ROUND_OVER:
  LDA WINNER
  BMI .ro_next
  TAX
  INC P_WINS,X
  LDA P_WINS,X
  CMP #2
  BCS .ro_match
  INC ROUND
.ro_next:
  JMP NEW_ROUND
.ro_match:
  JMP MATCH_END

MATCH_END:
  LDX #$FF
  TXS
  LDA #1
  STA MAG
  LDA #8
  JSR LOAD_SCENE
  JSR HIDE_SPRITES
  LDA #<VIC_REC
  STA PTR
  LDA #>VIC_REC
  STA PTR+1
  JSR DRAW_RECORDS
  JSR VDP_INT_ON
  LDA #3                        ; victory music
  JSR MUS_PLAY
  LDA #0
  STA VCNT
  STA ARMED
  LDA #150
  STA GO_DELAY
  JSR NT_CLEAR
  LDA #<VIC_T2
  STA PTR
  LDA #>VIC_T2
  STA PTR+1
  LDX #(32+9)
  LDY #13
  JSR BUF_PUT
  LDX WINNER
  LDA P_CHAR,X
  ASL A
  ASL A
  ASL A
  CLC
  ADC #<NAMEL
  STA PTR
  LDA #>NAMEL
  ADC #0
  STA PTR+1
  LDX #(64+12)
  LDY #8
  JSR BUF_PUT
  LDA #7
  STA NT_DIRTY
.me_loop:
  JSR WAIT_FRAME
  JSR READ_JOY
  INC VCNT
  JSR VIC_TEXT
  JSR DRAW_VICTORY
  LDA P_JOY
  ORA P_JOY+1
  AND #BTN_MASK
  BNE .me_pressed
  LDA GO_DELAY
  BNE .me_dec
  LDA #$01
  STA ARMED
  BRA .me_loop
.me_dec:
  DEC GO_DELAY
  BRA .me_loop
.me_pressed:
  LDA ARMED
  BEQ .me_loop
  LDA #$FF
  JSR MUS_PLAY
  JMP TITLE

VIC_TEXT:
  LDA VCNT
  AND #$0F
  BNE .vt_r
  LDA VCNT
  AND #$10
  BEQ .vt_off
  LDA #<VIC_T1
  STA PTR
  LDA #>VIC_T1
  STA PTR+1
  LDX #8
  LDY #16
  JSR BUF_PUT
  BRA .vt_d
.vt_off:
  LDX #8
  LDA #0
.vt_c:
  STA NT_BUF,X
  INX
  CPX #24
  BNE .vt_c
.vt_d:
  LDA NT_DIRTY
  ORA #1
  STA NT_DIRTY
.vt_r:
  RTS

DRAW_VICTORY:
  LDX WINNER
  LDA P_CHAR,X
  STA T4
  LDA VCNT
  AND #$1F
  TAY
  LDA JUMP_H,Y
  STA T0
  LDA #150
  SEC
  SBC T0
  STA T1
  SEC
  SBC #65
  STA SAT_BUFFER
  DEC A                         ; black layer: one pixel up and left
  STA SAT_BUFFER+28
  LDA T1
  SEC
  SBC #33
  STA SAT_BUFFER+4
  DEC A
  STA SAT_BUFFER+32
  LDA #113
  STA SAT_BUFFER+1
  STA SAT_BUFFER+5
  DEC A
  STA SAT_BUFFER+29
  STA SAT_BUFFER+33
  LDA VCNT
  AND #$20
  BEQ .dv_a
  LDA #T_SPEC
  BRA .dv_b
.dv_a:
  LDA #T_JUMP
.dv_b:
  ASL A
  ASL A
  STA SAT_BUFFER+2
  CLC
  ADC #140
  STA SAT_BUFFER+30
  LDA T0
  CMP #3
  BCS .dv_j
  LDA #B_A
  BRA .dv_l
.dv_j:
  LDA #B_JUMP
.dv_l:
  CLC
  ADC #16
  ASL A
  ASL A
  STA SAT_BUFFER+6
  CLC
  ADC #140
  STA SAT_BUFFER+34
  LDX T4
  LDA #SKIN_COL
  STA SAT_BUFFER+3
  LDA BOT_COL,X
  STA SAT_BUFFER+7
  LDA #1
  STA SAT_BUFFER+31
  STA SAT_BUFFER+35
  LDA #HIDE_Y
  STA SAT_BUFFER+8
  STA SAT_BUFFER+12
  STA SAT_BUFFER+16
  STA SAT_BUFFER+20
  STA SAT_BUFFER+24
  STA SAT_BUFFER+36
  STA SAT_BUFFER+40
  RTS

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

; ---------------------------------------------------------------
;  fighters
; ---------------------------------------------------------------
; X = player. new X position = CX + A (clamped); stops at the opponent
; when both are on the ground
MOVE_X:
  STA T0
  LDA P_CX,X
  CLC
  ADC T0
  CMP #XMINC
  BCS .mx_c1
  LDA #XMINC
.mx_c1:
  CMP #(XMAXC+1)
  BCC .mx_c2
  LDA #XMAXC
.mx_c2:
  STA T1
  LDA P_JUMP,X
  BNE .mx_ok
  TXA
  EOR #$01
  TAY
  LDA P_JUMP,Y
  BNE .mx_ok
  LDA T1
  SEC
  SBC P_CX,Y
  BCS .mx_a1
  EOR #$FF
  CLC
  ADC #$01
.mx_a1:
  CMP #MINSEP
  BCS .mx_ok
  STA T2
  LDA P_CX,X
  SEC
  SBC P_CX,Y
  BCS .mx_a2
  EOR #$FF
  CLC
  ADC #$01
.mx_a2:
  CMP T2
  BCS .mx_ok
  RTS
.mx_ok:
  LDA T1
  STA P_CX,X
  RTS

MOVE_RAW:
  CLC
  ADC P_CX,X
  CMP #XMINC
  BCS .mr_1
  LDA #XMINC
.mr_1:
  CMP #(XMAXC+1)
  BCC .mr_2
  LDA #XMAXC
.mr_2:
  STA P_CX,X
  RTS

RESOLVE:
  LDA P_JUMP
  ORA P_JUMP+1
  BNE .rs2_ret
  LDA P_CX+1
  SEC
  SBC P_CX
  BCS .rs2_p
  EOR #$FF
  CLC
  ADC #$01
  CMP #MINSEP
  BCS .rs2_ret
  LDA #$01
  BRA .rs2_do
.rs2_p:
  CMP #MINSEP
  BCS .rs2_ret
  LDA #$FF
.rs2_do:
  STA T3
  LDX #0
  JSR MOVE_RAW
  LDA T3
  EOR #$FF
  CLC
  ADC #$01
  LDX #1
  JSR MOVE_RAW
.rs2_ret:
  RTS

UPDATE_FIGHTER:
  LDA P_JOY,X
  AND #BTN_MASK
  STA T0
  LDA P_OLD,X
  EOR #$FF
  AND T0
  STA P_EDGE,X
  LDA T0
  STA P_OLD,X
  LDA P_JUMP,X
  BEQ .uf_gr
  DEC P_JUMP,X
  BNE .uf_gr
  LDA #0                        ; landed
  STA P_VX,X
  LDA P_ST,X
  CMP #ST_JUMP
  BNE .uf_gr
  LDA #ST_IDLE
  STA P_ST,X
  LDA #0
  STA P_ATK,X
.uf_gr:
  LDA P_VX,X
  BEQ .uf_nov
  JSR MOVE_X
.uf_nov:
  LDA P_ST,X
  BNE .u1
  JMP FS_IDLE
.u1:
  CMP #ST_JUMP
  BNE .u2
  JMP FS_JUMP
.u2:
  CMP #ST_SPEC
  BNE .u3
  JMP FS_SPEC
.u3:
  CMP #ST_HIT
  BNE .u4
  JMP FS_HIT
.u4:
  CMP #ST_WIN
  BNE .u5
  JMP FS_WIN
.u5:
  CMP #ST_KO
  BEQ .u6
  JMP FS_ATTACK
.u6:
  RTS

FS_IDLE:
  TXA
  EOR #$01
  TAY
  LDA P_CX,Y
  CMP P_CX,X
  LDA #0
  BCS .fi_f
  LDA #1
.fi_f:
  STA P_FACE,X
  LDA P_BUF,X
  BNE .fi_buf
  LDA P_EDGE,X
  BEQ .fi_nb
  LDA #SPEC_WIN
  STA P_BUF,X
  LDA P_JOY,X
  AND #BTN_MASK
  STA P_BTN,X
  BRA .fi_nb
.fi_buf:
  LDA P_JOY,X
  AND #BTN_MASK
  ORA P_BTN,X
  STA P_BTN,X
  DEC P_BUF,X
  BNE .fi_nb
  JMP RESOLVE_ATTACK
.fi_nb:
  LDA P_JOY,X
  AND #%00000001
  BEQ .fi_nj
  LDA #JUMP_LEN
  STA P_JUMP,X
  LDA #ST_JUMP
  STA P_ST,X
  LDA #0
  STA P_ATK,X
  STA P_HITD,X
  STA P_BUF,X
  STA P_VX,X
  LDA P_JOY,X
  AND #%00001000
  BEQ .fi_jl
  LDA #2
  STA P_VX,X
.fi_jl:
  LDA P_JOY,X
  AND #%00000100
  BEQ .fi_jd
  LDA #$FE
  STA P_VX,X
.fi_jd:
  LDA #5
  JMP SFX_PLAY
.fi_nj:
  LDA P_JOY,X
  AND #%00001100
  BNE .fi_walk
  LDA #0
  STA P_WALK,X
  RTS
.fi_walk:
  INC P_WALK,X
  LDA P_JOY,X
  AND #%00001000
  BEQ .fi_wl
  LDA P_FACE,X
  BEQ .fi_r2
  LDA #1
  BRA .fi_rm
.fi_r2:
  LDA #2
.fi_rm:
  JSR MOVE_X
.fi_wl:
  LDA P_JOY,X
  AND #%00000100
  BEQ .fi_wd
  LDA P_FACE,X
  BNE .fi_l2
  LDA #$FF
  BRA .fi_lm
.fi_l2:
  LDA #$FE
.fi_lm:
  JSR MOVE_X
.fi_wd:
  RTS

RESOLVE_ATTACK:
  LDA P_BTN,X
  CMP #BTN_MASK
  BNE .ra_one
  LDA P_SP,X
  CMP #SP_MAX
  BCC .ra_kick
  JMP START_SPECIAL
.ra_one:
  AND #%00010000
  BNE .ra_punch
.ra_kick:
  LDA #2
  BRA .ra_go
.ra_punch:
  LDA #1
.ra_go:
  STA P_ATK,X
  TAY
  LDA ATK_LEN,Y
  STA P_TMR,X
  LDA #0
  STA P_HITD,X
  TYA
  CLC
  ADC #1                        ; 1 -> ST_PUNCH (2), 2 -> ST_KICK (3)
  STA P_ST,X
  LDA #4                        ; swing sound
  JMP SFX_PLAY

START_SPECIAL:
  LDA #0
  STA P_SP,X
  LDA #1
  STA BARS_D
  LDY P_CHAR,X
  LDA SP_LEN,Y
  STA P_TMR,X
  LDA #3
  STA P_ATK,X
  LDA #0
  STA P_HITD,X
  LDA #ST_SPEC
  STA P_ST,X
  LDA SP_TYPE,Y
  CMP #2
  BNE .ss2_r
  LDA #JUMP_LEN
  STA P_JUMP,X
.ss2_r:
  LDA P_CHAR,X                  ; every special has its own sound
  CLC
  ADC #7
  JMP SFX_PLAY

FS_ATTACK:
  DEC P_TMR,X
  BEQ .fa_end
  LDY P_ATK,X
  LDA P_TMR,X
  CMP ATK_HITAT,Y
  BNE .fa_ret
  TYA
  JMP TRY_HIT
.fa_ret:
  RTS
.fa_end:
  LDA #ST_IDLE
  STA P_ST,X
  LDA #0
  STA P_ATK,X
  RTS

FS_JUMP:
  LDA P_ATK,X
  BNE .fj_act
  LDA P_EDGE,X
  BEQ .fj_ret
  AND #%00010000
  BNE .fj_p
  LDA #2
  BRA .fj_s
.fj_p:
  LDA #1
.fj_s:
  STA P_ATK,X
  LDA #0
  STA P_HITD,X
  LDA #4
  JMP SFX_PLAY
.fj_ret:
  RTS
.fj_act:
  LDA P_HITD,X
  BNE .fj_ret
  LDA P_ATK,X
  JMP TRY_HIT

FS_HIT:
  DEC P_TMR,X
  BNE .fh_more
  LDA P_JUMP,X
  BNE .fh_wait
  LDA #0
  STA P_VX,X
  STA P_BLK,X
  LDA #ST_IDLE
  STA P_ST,X
  RTS
.fh_more:
  LDA P_TMR,X                   ; the slide only lasts for the first frames
  CMP #9
  BCS .fh_ret
  LDA P_JUMP,X
  BNE .fh_ret
  LDA #0
  STA P_VX,X
.fh_ret:
  RTS
.fh_wait:
  LDA #1
  STA P_TMR,X
  RTS

FS_WIN:
  LDA P_JUMP,X
  BNE .fw_r
  LDA #20
  STA P_JUMP,X
.fw_r:
  RTS

FS_SPEC:
  DEC P_TMR,X
  BNE .fs_go
  LDA #0
  STA P_ATK,X
  LDA P_JUMP,X
  BEQ .fs_idle
  LDA #ST_JUMP
  STA P_ST,X
  RTS
.fs_idle:
  LDA #ST_IDLE
  STA P_ST,X
  RTS
.fs_go:
  LDY P_CHAR,X
  LDA SP_LEN,Y
  SEC
  SBC P_TMR,X
  STA T0                        ; frames elapsed
  LDA SP_TYPE,Y
  BEQ .fs_proj
  CMP #1
  BEQ .fs_dash
  LDA T0                        ; uppercut: hits while rising
  CMP #10
  BCS .fs_ret
  LDA #3
  JMP TRY_HIT
.fs_ret:
  RTS
.fs_proj:
  LDA T0
  CMP #8
  BNE .fs_ret
  LDA #1
  STA PR_ON,X
  LDA P_FACE,X
  STA PR_DIR,X
  BNE .fs_pl
  LDA P_CX,X
  CLC
  ADC #16
  BRA .fs_ps
.fs_pl:
  LDA P_CX,X
  SEC
  SBC #16
.fs_ps:
  STA PR_X,X
  RTS
.fs_dash:
  LDA T0
  CMP #6
  BCC .fs_ret
  CMP #20
  BCS .fs_ret
  LDA SP_SPD,Y
  LDY P_FACE,X
  BEQ .fs_dp
  EOR #$FF
  CLC
  ADC #$01
.fs_dp:
  JSR MOVE_X
  LDA #3
  JMP TRY_HIT

; X = attacker, A = kind (1 punch, 2 kick, 3 special)
TRY_HIT:
  STA T6
  LDA P_HITD,X
  BNE .th_no
  TXA
  EOR #$01
  STA T7
  TAY
  LDA P_CX,Y
  SEC
  SBC P_CX,X
  BCS .th_pos
  EOR #$FF
  CLC
  ADC #$01
  STA T0
  LDA P_FACE,X
  BEQ .th_no
  BRA .th_ps
.th_pos:
  STA T0
  LDA P_FACE,X
  BNE .th_no
.th_ps:
  LDA P_JUMP,X
  TAY
  LDA JUMP_H,Y
  STA T1
  LDY T7
  LDA P_JUMP,Y
  TAY
  LDA JUMP_H,Y
  SEC
  SBC T1
  BCS .th_v
  EOR #$FF
  CLC
  ADC #$01
.th_v:
  CMP #VTOL
  BCS .th_no
  LDY T6
  CPY #3
  BEQ .th_sp
  LDA ATK_RANGE,Y
  STA T1
  LDA ATK_DMG,Y
  STA T2
  BRA .th_p2
.th_sp:
  LDY P_CHAR,X
  LDA SP_RANGE,Y
  STA T1
  LDA SP_DMG,Y
  STA T2
.th_p2:
  LDA T0
  CMP T1
  BCS .th_no
  LDA #1
  STA P_HITD,X
  LDA P_FACE,X
  STA T5
  JMP APPLY_HIT
.th_no:
  RTS

; X = attacker, T7 = defender, T6 = kind, T5 = direction (0 right), T2 = damage
APPLY_HIT:
  LDY T7
  LDA #0
  STA P_BLK,Y
  LDA P_ST,Y
  BNE .ah_nb
  LDA P_JUMP,Y
  BNE .ah_nb
  LDA P_FACE,Y
  BNE .ah_bl
  LDA P_JOY,Y
  AND #%00000100
  BRA .ah_bt
.ah_bl:
  LDA P_JOY,Y
  AND #%00001000
.ah_bt:
  BEQ .ah_nb
  LDA #1
  STA P_BLK,Y
  LDA T2
  LSR A
  LSR A
  BNE .ah_bd
  LDA #1
.ah_bd:
  STA T2
.ah_nb:
  LDA P_HP,Y
  SEC
  SBC T2
  BCS .ah_hp
  LDA #0
.ah_hp:
  STA P_HP,Y
  LDA T2
  ASL A
  CLC
  ADC P_SP,X
  CMP #(SP_MAX+1)
  BCC .ah_s1
  LDA #SP_MAX
.ah_s1:
  STA P_SP,X
  LDA T2
  CLC
  ADC P_SP,Y
  CMP #(SP_MAX+1)
  BCC .ah_s2
  LDA #SP_MAX
.ah_s2:
  STA P_SP,Y
  LDA #1
  STA BARS_D
  LDA #6                        ; impact spark
  STA SPK_T
  LDA P_CX,Y
  STA SPK_X
  LDA P_JUMP,Y
  TAY
  LDA JUMP_H,Y
  STA T0
  LDA #(GROUND_Y-44)
  SEC
  SBC T0
  STA SPK_Y
  LDY T7
  LDA P_HP,Y
  BEQ .ah_sko
  LDA P_BLK,Y
  BNE .ah_sbl
  LDA T6
  CMP #1
  BEQ .ah_x1
  LDA #2
  BRA .ah_ssf
.ah_x1:
  LDA #1
  BRA .ah_ssf
.ah_sbl:
  LDA #3
  BRA .ah_ssf
.ah_sko:
  LDA #6
.ah_ssf:
  JSR SFX_PLAY
  LDY T7
  LDA P_HP,Y
  BNE .ah_alive
  LDA #ST_KO
  STA P_ST,Y
  LDA #0
  STA P_TMR,Y
  STA P_ATK,Y
  STA P_BUF,Y
  STA P_BLK,Y
  LDA #18
  STA P_JUMP,Y
  LDA T5
  BNE .ah_kl
  LDA #3
  BRA .ah_kv
.ah_kl:
  LDA #$FD
.ah_kv:
  STA P_VX,Y
  RTS
.ah_alive:
  LDA #ST_HIT
  STA P_ST,Y
  LDA #0
  STA P_ATK,Y
  STA P_BUF,Y
  LDA P_BLK,Y
  BEQ .ah_hit
  LDA #6
  STA P_TMR,Y
  LDA #1
  STA T3
  BRA .ah_sl
.ah_hit:
  LDY T6
  LDA ATK_SLIDE,Y
  STA T3
  LDA ATK_STUN,Y
  LDY T7
  STA P_TMR,Y
.ah_sl:
  LDY T7
  LDA T3
  LDX T5
  BEQ .ah_sp
  EOR #$FF
  CLC
  ADC #$01
.ah_sp:
  STA P_VX,Y
  RTS

; projectile of player X
UPDATE_PROJ:
  LDA PR_ON,X
  BEQ .pj_ret
  LDY P_CHAR,X
  LDA SP_SPD,Y
  LDY PR_DIR,X
  BEQ .pj_p
  EOR #$FF
  CLC
  ADC #$01
.pj_p:
  CLC
  ADC PR_X,X
  STA PR_X,X
  CMP #16
  BCC .pj_off
  CMP #241
  BCS .pj_off
  TXA
  EOR #$01
  TAY
  LDA PR_X,X
  SEC
  SBC P_CX,Y
  BCS .pj_a
  EOR #$FF
  CLC
  ADC #$01
.pj_a:
  CMP #14
  BCS .pj_ret
  LDA P_JUMP,Y
  TAY
  LDA JUMP_H,Y
  CMP #32
  BCS .pj_ret
  LDA #0
  STA PR_ON,X
  TXA
  EOR #$01
  STA T7
  LDY P_CHAR,X
  LDA SP_DMG,Y
  STA T2
  LDA #3
  STA T6
  LDA PR_DIR,X
  STA T5
  JMP APPLY_HIT
.pj_off:
  LDA #0
  STA PR_ON,X
.pj_ret:
  RTS

; ---------------------------------------------------------------
;  drawing: SAT_BUFFER (RAM) is copied to VRAM by the NMI
;  SAT: 0 P1 top, 1 P1 legs, 2 P2 top, 3 P2 legs, 4-5 projectiles, 6 spark,
;  7-10 black layers, 11-12 select arrows
; ---------------------------------------------------------------
DRAW_ALL:
  LDX #0
  JSR DRAW_FIGHTER
  LDX #1
  JSR DRAW_FIGHTER
  LDX #0
  JSR DRAW_PROJ
  LDX #1
  JSR DRAW_PROJ
  LDA SPK_T
  BNE .da_sp
  LDA #HIDE_Y
  STA SAT_BUFFER+24
  RTS
.da_sp:
  LDA SPK_Y
  SEC
  SBC #16
  STA SAT_BUFFER+24
  LDA SPK_X
  SEC
  SBC #15
  STA SAT_BUFFER+25
  LDA #128
  STA SAT_BUFFER+26
  LDA #$0F
  STA SAT_BUFFER+27
  RTS

DRAW_PROJ:
  TXA
  ASL A
  ASL A
  CLC
  ADC #16
  TAY
  LDA PR_ON,X
  BNE .dp_on
  LDA #HIDE_Y
  STA SAT_BUFFER,Y
  RTS
.dp_on:
  LDA #(GROUND_Y-55)            ; art in rows 0-7: chest height
  STA SAT_BUFFER,Y
  LDA PR_X,X
  SEC
  SBC #15
  STA SAT_BUFFER+1,Y
  LDA P_CHAR,X
  STA T4
  LDA PR_DIR,X
  ASL A
  ASL A
  STA T5
  LDX T4
  LDA PRJ_NAME,X
  CLC
  ADC T5
  STA SAT_BUFFER+2,Y
  LDA PRJ_COL,X
  STA SAT_BUFFER+3,Y
  RTS

; X = player (X is destroyed)
DRAW_FIGHTER:
  TXA
  ASL A
  ASL A
  ASL A
  STA T6
  LDA P_JUMP,X
  TAY
  LDA JUMP_H,Y
  STA T0
  LDA #GROUND_Y
  SEC
  SBC T0
  STA T1
  LDA P_ST,X
  CMP #ST_KO
  BNE .df_std
  LDA P_JUMP,X
  BNE .df_std
  JMP DRAW_LYING
.df_std:
  LDY T6
  LDA T1
  SEC
  SBC #65
  STA SAT_BUFFER,Y
  LDA T1
  SEC
  SBC #33
  STA SAT_BUFFER+4,Y
  LDA P_CX,X                    ; both directions: body centre at column 7
  SEC
  SBC #15
  STA SAT_BUFFER+1,Y
  STA SAT_BUFFER+5,Y
  JSR GET_POSE
  LDA P_FACE,X
  BEQ .df_nr
  LDA T2
  CLC
  ADC #8
  STA T2
  LDA T3
  CLC
  ADC #4
  STA T3
.df_nr:
  LDA T2
  ASL A
  ASL A
  STA SAT_BUFFER+2,Y
  LDA T3
  CLC
  ADC #16
  ASL A
  ASL A
  STA SAT_BUFFER+6,Y
  LDA P_CHAR,X
  STA T4
  LDX T4
  LDA #SKIN_COL
  STA SAT_BUFFER+3,Y
  LDA BOT_COL,X
  STA SAT_BUFFER+7,Y
  JMP COPY_OUTLINE

; black outline sprites (entries 7-10) follow the fill sprites of fighter T6/8,
; one pixel up and left: with magnified sprites the outline is 1 pixel thick
COPY_OUTLINE:
  LDX T6
  LDA SAT_BUFFER,X
  DEC A
  STA SAT_BUFFER+28,X
  LDA SAT_BUFFER+1,X
  DEC A
  STA SAT_BUFFER+29,X
  LDA SAT_BUFFER+2,X
  CLC
  ADC #140
  STA SAT_BUFFER+30,X
  LDA #1
  STA SAT_BUFFER+31,X
  LDA SAT_BUFFER+4,X
  DEC A
  STA SAT_BUFFER+32,X
  LDA SAT_BUFFER+5,X
  DEC A
  STA SAT_BUFFER+33,X
  LDA SAT_BUFFER+6,X
  CLC
  ADC #140
  STA SAT_BUFFER+34,X
  LDA #1
  STA SAT_BUFFER+35,X
  RTS

DRAW_LYING:
  LDY T6
  LDA #(GROUND_Y-33)
  STA SAT_BUFFER,Y
  STA SAT_BUFFER+4,Y
  LDA P_CX,X
  SEC
  SBC #32
  BCC .dl_0
  CMP #1
  BCS .dl_a
.dl_0:
  LDA #1
.dl_a:
  STA SAT_BUFFER+1,Y
  CLC
  ADC #32
  STA SAT_BUFFER+5,Y
  LDA P_CHAR,X
  STA T4
  LDA P_FACE,X
  STA T5
  LDX T4
  LDA T5
  BNE .dl_r
  LDA #96
  STA SAT_BUFFER+2,Y
  LDA #100
  STA SAT_BUFFER+6,Y
  LDA #SKIN_COL
  STA SAT_BUFFER+3,Y
  LDA BOT_COL,X
  STA SAT_BUFFER+7,Y
  JMP COPY_OUTLINE
.dl_r:
  LDA #104
  STA SAT_BUFFER+2,Y
  LDA #108
  STA SAT_BUFFER+6,Y
  LDA BOT_COL,X
  STA SAT_BUFFER+3,Y
  LDA #SKIN_COL
  STA SAT_BUFFER+7,Y
  JMP COPY_OUTLINE

; X = player -> T2 = top pose, T3 = legs pose (Y is kept)
GET_POSE:
  LDA #T_IDLE
  STA T2
  LDA #B_A
  STA T3
  LDA P_ST,X
  BEQ .gp_idle
  CMP #ST_JUMP
  BEQ .gp_jump
  CMP #ST_PUNCH
  BEQ .gp_punch
  CMP #ST_KICK
  BEQ .gp_kick
  CMP #ST_SPEC
  BEQ .gp_spec
  CMP #ST_WIN
  BEQ .gp_win
  LDA P_BLK,X                   ; hit / KO in the air
  BNE .gp_block
  LDA #T_HIT
  STA T2
  RTS
.gp_block:
  LDA #T_BLOCK
  STA T2
  RTS
.gp_idle:
  LDA P_FACE,X
  BNE .gi_l
  LDA P_JOY,X
  AND #%00000100
  BRA .gi_t
.gi_l:
  LDA P_JOY,X
  AND #%00001000
.gi_t:
  BEQ .gi_w
  LDA #T_BLOCK
  STA T2
.gi_w:
  LDA P_WALK,X
  AND #$08
  BEQ .gi_r
  LDA #B_B
  STA T3
.gi_r:
  RTS
.gp_jump:
  LDA #T_JUMP
  STA T2
  LDA #B_JUMP
  STA T3
  LDA P_ATK,X
  BEQ .gj_r
  CMP #2
  BEQ .gj_k
  LDA #T_PUNCH
  STA T2
  RTS
.gj_k:
  LDA #T_KICK
  STA T2
  LDA #B_KICK
  STA T3
.gj_r:
  RTS
.gp_punch:
  LDA #T_PUNCH
  STA T2
  RTS
.gp_kick:
  LDA #T_KICK
  STA T2
  LDA #B_KICK
  STA T3
  RTS
.gp_spec:
  LDY P_CHAR,X
  LDA SP_TOP,Y
  STA T2
  LDA SP_BOT,Y
  STA T3
  LDY T6
  RTS
.gp_win:
  LDA #T_JUMP
  STA T2
  RTS

HIDE_SPRITES:
  LDX #0
  LDA #HIDE_Y
.hs_l:
  STA SAT_BUFFER,X
  INX
  INX
  INX
  INX
  CPX #52
  BNE .hs_l
  RTS

; ---------------------------------------------------------------
; NMI (vblank): copies the sprite table and the dirty HUD rows
; ---------------------------------------------------------------
NMI_TASK:
  INC FRAME_CNT
  LDA VREG
  LDA #<VDP_SPRITE_ATT_BASE
  STA VREG
  LDA #(VDP_WRITE_VRAM_BIT | >VDP_SPRITE_ATT_BASE)
  STA VREG
  LDX #$00
.copy_sat:
  LDA SAT_BUFFER,X
  STA VDATA
  INX
  CPX #53
  BNE .copy_sat
  LDA NT_DIRTY
  BEQ .nt_done
  LSR A
  BCC .nt_1
  PHA
  LDX #0
  JSR NMI_ROW
  PLA
.nt_1:
  LSR A
  BCC .nt_2
  PHA
  LDX #32
  JSR NMI_ROW
  PLA
.nt_2:
  LSR A
  BCC .nt_3
  LDX #64
  JSR NMI_ROW
.nt_3:
  LDA #0
  STA NT_DIRTY
.nt_done:
  JSR SOUND_TICK
  RTS

NMI_ROW:
  STX VREG
  LDA #(VDP_WRITE_VRAM_BIT | >VDP_NAME_TABLE_BASE)
  STA VREG
.nr2_l:
  LDA NT_BUF,X
  STA VDATA
  INX
  TXA
  AND #$1F
  BNE .nr2_l
  RTS

WAIT_FRAME:
  LDA FRAME_CNT
  CMP LAST_FRAME
  BEQ WAIT_FRAME
  STA LAST_FRAME
  RTS

VDP_INT_OFF:
  LDA INT_FLAG
  BEQ .io_ret
  LDA FRAME_CNT
.io_wait:
  CMP FRAME_CNT
  BEQ .io_wait
  LDA #$C6
  ORA MAG
  STA VREG
  LDA #(VDP_REGISTER_BITS | 1)
  STA VREG
  LDA #0
  STA INT_FLAG
.io_ret:
  RTS

VDP_INT_ON:
  LDA #$E6
  ORA MAG
  STA VREG
  LDA #(VDP_REGISTER_BITS | 1)
  STA VREG
  LDA #1
  STA INT_FLAG
  RTS

; ---------------------------------------------------------------
; scene loader: A = scene (0 title, 1 select, 2-7 stages).
; leaves the display on and the VDP interrupt off
; ---------------------------------------------------------------
LOAD_SCENE:
  STA SCN
  JSR VDP_INT_OFF
  LDA #$86                      ; display off while loading
  ORA MAG
  STA VREG
  LDA #(VDP_REGISTER_BITS | 1)
  STA VREG
  LDX SCN
  LDA SC_PATL,X
  STA PTR
  LDA SC_PATH,X
  STA PTR+1
  LDA #$00
  STA VREG
  LDA #$40
  STA VREG
  JSR UNPACK
  LDX SCN
  LDA SC_COLL,X
  STA PTR
  LDA SC_COLH,X
  STA PTR+1
  LDA #$00
  STA VREG
  LDA #$60
  STA VREG
  JSR UNPACK
  LDX SCN
  LDA SC_NAML,X
  STA PTR
  LDA SC_NAMH,X
  STA PTR+1
  LDA #$00
  STA VREG
  LDA #$78
  STA VREG
  JSR UNPACK
  JSR LOAD_COMMON
  LDA #0
  STA NT_DIRTY
  LDA #$C6
  ORA MAG
  STA VREG
  LDA #(VDP_REGISTER_BITS | 1)
  STA VREG
  RTS

; RLE stream (PTR) -> VRAM:  0 = end, 1-127 = literal run, 128-255 = repeat (n-126)
UNPACK:
.un_next:
  JSR RD_BYTE
  BEQ .un_end
  BMI .un_rep
  TAX
.un_lit:
  JSR RD_BYTE
  STA VDATA
  DEX
  BNE .un_lit
  BRA .un_next
.un_rep:
  AND #$7F
  CLC
  ADC #2
  TAX
  JSR RD_BYTE
.un_rl:
  STA VDATA
  DEX
  BNE .un_rl
  BRA .un_next
.un_end:
  RTS

RD_BYTE:
  LDA (PTR)
  INC PTR
  BNE .rb_x
  INC PTR+1
.rb_x:
  ORA #$00
  RTS

; font in the 3 thirds + HUD tiles in the first third
LOAD_COMMON:
  LDA #0
  STA T4
.lc_t:
  LDA #$00
  STA VREG
  LDA T4
  ASL A
  ASL A
  ASL A
  CLC
  ADC #$41
  STA VREG
  LDA #<FONT_PAT
  STA PTR
  LDA #>FONT_PAT
  STA PTR+1
  LDA #0
  STA T0
  LDA #2
  STA T1
  JSR VCOPY
  LDA #$00
  STA VREG
  LDA T4
  ASL A
  ASL A
  ASL A
  CLC
  ADC #$61
  STA VREG
  LDY #0
  LDA #$F1
.lc_c:
  STA VDATA
  STA VDATA
  DEY
  BNE .lc_c
  INC T4
  LDA T4
  CMP #3
  BNE .lc_t
  LDA #$00
  STA VREG
  LDA #$44
  STA VREG
  LDA #<HUD_PAT
  STA PTR
  LDA #>HUD_PAT
  STA PTR+1
  LDA #0
  STA T0
  LDA #1
  STA T1
  JSR VCOPY
  LDA #$00
  STA VREG
  LDA #$64
  STA VREG
  LDA #<HUD_COL
  STA PTR
  LDA #>HUD_COL
  STA PTR+1
  LDA #0
  STA T0
  LDA #1
  STA T1
  JSR VCOPY
  RTS

; copies T1:T0 bytes from (PTR) to the VRAM address already set
VCOPY:
  LDY #0
.vc_cp:
  LDA (PTR),Y
  STA VDATA
  INY
  BNE .vc_y
  INC PTR+1
.vc_y:
  LDA T0
  BNE .vc_d0
  DEC T1
.vc_d0:
  DEC T0
  LDA T0
  ORA T1
  BNE .vc_cp
  RTS

; records: .byte row, column, length, tiles...   (end: row = $FF)
DRAW_RECORDS:
.dr_next:
  LDY #0
  LDA (PTR),Y
  CMP #$FF
  BEQ .dr_end
  STA T0
  INY
  LDA (PTR),Y
  STA T1
  INY
  LDA (PTR),Y
  STA T2
  LDA T0
  AND #$07
  ASL A
  ASL A
  ASL A
  ASL A
  ASL A
  CLC
  ADC T1
  STA VREG
  LDA T0
  LSR A
  LSR A
  LSR A
  CLC
  ADC #(VDP_WRITE_VRAM_BIT | >VDP_NAME_TABLE_BASE)
  STA VREG
  INY
.dr_copy:
  LDA (PTR),Y
  STA VDATA
  INY
  DEC T2
  BNE .dr_copy
  TYA
  CLC
  ADC PTR
  STA PTR
  BCC .dr_next
  INC PTR+1
  BRA .dr_next
.dr_end:
  RTS

; ---------------------------------------------------------------
; VDP
; ---------------------------------------------------------------
VDP_SET_REGISTERS:
  PHA
  PHY
  LDY #$87
  LDX #$07
INIT1:
  LDA ITAB,X
  JSR SREG
  DEY
  DEX
  BNE INIT1
  LDA ITAB
  JSR SREG
  PLY
  PLA
  RTS

SREG:
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
   LDY #$40
   LDA #0
   STA VREG
   STY VREG
   LDX #$C0
NEXF:
   LDY #0
FILL_:
   LDA #$00
   STA VDATA
   INY
   BNE FILL_
   INX
   BNE NEXF
   PLY
   PLX
   PLA
   RTS

ITAB:
   .byte $02,$C6,$0E,$FF
   .byte $03,$76,$03,$01


; ===============================================================
;  SOUND  (2 x AY-3-8910 written in parallel, called from the NMI)
;  MUS_PLAY: A = 1 intro, 2 round jingle, 3 victory, $FF stop
;  SFX_PLAY: A = effect 1-13 (ignored while music is playing)
; ===============================================================
MUS_PLAY:
  STA MUS_REQ
  RTS

SFX_PLAY:
  STA SFX_REQ
  RTS

; A = value, Y = AY register (both chips)
AYW:
  STY AYR_LATCH
  STA AYR_WRITE
  STY AYL_LATCH
  STA AYL_WRITE
  RTS

AY_INIT:
  LDY #0
  LDA #0
.ai_l:
  JSR AYW
  INY
  CPY #7
  BNE .ai_l
  LDA #$38
  LDY #7
  JSR AYW
  LDA #0
  LDY #8
  JSR AYW
  INY
  JSR AYW
  INY
  JSR AYW
  RTS

SOUND_TICK:
  PHY
  LDA MUS_REQ
  BEQ .sk_nr
  CMP #$FF
  BNE .sk_go
  JSR MUS_STOP
  BRA .sk_clr
.sk_go:
  JSR MUS_START
.sk_clr:
  LDA #0
  STA MUS_REQ
.sk_nr:
  LDA MUS_ON
  BEQ .sk_sfx
  LDA #0
  STA SFX_REQ
  JSR MUS_TICK
  PLY
  RTS
.sk_sfx:
  LDA SFX_REQ
  BEQ .sk_sa
  JSR SFX_START
  LDA #0
  STA SFX_REQ
.sk_sa:
  LDA SFX_ON
  BEQ .sk_ret
  JSR SFX_TICK
.sk_ret:
  PLY
  RTS

MUS_STOP:
  LDA #0
  STA MUS_ON
  STA SFX_ON
  LDY #8
.mp_l:
  JSR AYW
  INY
  CPY #11
  BNE .mp_l
  RTS

MUS_START:
  SEC
  SBC #1
  ASL A
  STA N0
  ASL A
  CLC
  ADC N0
  STA MUS_S6
  TAX
  LDY #0
.ms_c:
  LDA SONG_TAB,X
  STA VP,Y
  INX
  INY
  CPY #6
  BNE .ms_c
  LDX #0
.ms_v:
  LDA #1
  STA VT,X
  LDA #0
  STA VVOL,X
  STA VEND,X
  INX
  INX
  CPX #6
  BNE .ms_v
  LDA #0
  STA MUS_ENDED
  LDA #1
  STA MUS_ON
  LDA #$38
  LDY #7
  JSR AYW
  RTS

MUS_TICK:
  LDX #0
.mt_v:
  DEC VT,X
  BEQ .mt_fetch
  JMP .mt_vol
.mt_fetch:
  LDA (VP,X)
  INC VP,X
  BNE .mt_a
  INC VP+1,X
.mt_a:
  CMP #$FF
  BEQ .mt_end
  CMP #$FE
  BEQ .mt_loop
  STA N0
  LDA (VP,X)
  INC VP,X
  BNE .mt_b
  INC VP+1,X
.mt_b:
  STA VT,X
  LDA N0
  BEQ .mt_rest
  TAY
  LDA PER_LO,Y
  STA VPL,X
  LDA PER_HI,Y
  STA VPH,X
  LDA VSTART,X
  STA VVOL,X
  LDA #0
  STA VDC,X
  BRA .mt_vol
.mt_rest:
  LDA #0
  STA VVOL,X
  BRA .mt_vol
.mt_loop:
  TXA
  CLC
  ADC MUS_S6
  TAY
  LDA SONG_TAB,Y
  STA VP,X
  LDA SONG_TAB+1,Y
  STA VP+1,X
  BRA .mt_fetch
.mt_end:
  LDA #<END_MARK
  STA VP,X
  LDA #>END_MARK
  STA VP+1,X
  LDA #0
  STA VVOL,X
  LDA #1
  STA VT,X
  LDA VEND,X
  BNE .mt_vol
  LDA #1
  STA VEND,X
  INC MUS_ENDED
.mt_vol:
  INC VDC,X
  LDA VDC,X
  AND #3
  BNE .mt_w
  LDA VVOL,X
  CMP #6
  BCC .mt_w
  DEC VVOL,X
.mt_w:
  TXA
  TAY
  LDA VPL,X
  JSR AYW
  INY
  LDA VPH,X
  JSR AYW
  TXA
  LSR A
  CLC
  ADC #8
  TAY
  LDA VVOL,X
  JSR AYW
  INX
  INX
  CPX #6
  BEQ .mt_done
  JMP .mt_v
.mt_done:
  LDA MUS_ENDED
  CMP #3
  BNE .mt_r
  JSR MUS_STOP
.mt_r:
  RTS

SFX_START:
  ASL A
  ASL A
  ASL A
  TAX
  LDA SFX_TAB,X
  STA SFX_TL
  LDA SFX_TAB+1,X
  STA SFX_TH
  LDA SFX_TAB+2,X
  STA SFX_SL
  LDA SFX_TAB+3,X
  STA SFX_NZ
  LDA SFX_TAB+4,X
  STA SFX_TV
  LDA SFX_TAB+5,X
  STA SFX_NV
  LDA SFX_TAB+6,X
  STA SFX_ON
  LDA SFX_TAB+7,X
  STA SFX_FL
  LDA SFX_NZ
  BEQ .sx_nn
  LDA #$2E                      ; tone on A, noise on B
  BRA .sx_m
.sx_nn:
  LDA #$3E
.sx_m:
  LDY #7
  JSR AYW
  LDA SFX_NZ
  LDY #6
  JSR AYW
  RTS

SFX_TICK:
  DEC SFX_ON
  BEQ .sf_off
  LDA SFX_TL
  CLC
  ADC SFX_SL
  STA SFX_TL
  LDA SFX_SL
  BMI .sf_neg
  LDA SFX_TH
  ADC #0
  BRA .sf_h
.sf_neg:
  LDA SFX_TH
  ADC #$FF
.sf_h:
  AND #$0F
  STA SFX_TH
  LDA SFX_ON
  AND #1
  BNE .sf_w
  LDA SFX_TV
  BEQ .sf_d1
  DEC SFX_TV
.sf_d1:
  LDA SFX_NV
  BEQ .sf_w
  DEC SFX_NV
.sf_w:
  LDA SFX_TL
  LDX SFX_FL
  BEQ .sf_p
  LDA FRAME_CNT
  ASL A
  EOR FRAME_CNT
  AND #$1F
  CLC
  ADC SFX_TL
.sf_p:
  LDY #0
  JSR AYW
  LDA SFX_TH
  INY
  JSR AYW
  LDA SFX_TV
  LDY #8
  JSR AYW
  LDA SFX_NV
  LDY #9
  JSR AYW
  RTS
.sf_off:
  LDA #0
  LDY #8
  JSR AYW
  INY
  JSR AYW
  RTS

; ===============================================================
;  DATA (generated)
; ===============================================================
FONT_PAT:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$20,$20,$20,$00,$20,$20,$00,$00
  .byte $50,$50,$50,$00,$00,$00,$00,$00,$50,$50,$F8,$50,$F8,$50,$50,$00
  .byte $20,$78,$A0,$70,$28,$F0,$20,$00,$C0,$C8,$10,$20,$40,$98,$18,$00
  .byte $40,$A0,$A0,$40,$A8,$90,$68,$00,$20,$20,$40,$00,$00,$00,$00,$00
  .byte $20,$40,$80,$80,$80,$40,$20,$00,$20,$10,$08,$08,$08,$10,$20,$00
  .byte $20,$A8,$70,$20,$70,$A8,$20,$00,$00,$20,$20,$F8,$20,$20,$00,$00
  .byte $00,$00,$00,$00,$20,$20,$40,$00,$00,$00,$00,$F8,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$20,$20,$00,$00,$00,$08,$10,$20,$40,$80,$00,$00
  .byte $70,$88,$98,$A8,$C8,$88,$70,$00,$20,$60,$20,$20,$20,$20,$70,$00
  .byte $70,$88,$08,$30,$40,$80,$F8,$00,$F8,$08,$10,$30,$08,$88,$70,$00
  .byte $10,$30,$50,$90,$F8,$10,$10,$00,$F8,$80,$F0,$08,$08,$88,$70,$00
  .byte $38,$40,$80,$F0,$88,$88,$70,$00,$F8,$08,$10,$20,$40,$40,$40,$00
  .byte $70,$88,$88,$70,$88,$88,$70,$00,$70,$88,$88,$78,$08,$10,$E0,$00
  .byte $00,$00,$20,$00,$20,$00,$00,$00,$00,$00,$20,$00,$20,$20,$40,$00
  .byte $10,$20,$40,$80,$40,$20,$10,$00,$00,$00,$F8,$00,$F8,$00,$00,$00
  .byte $40,$20,$10,$08,$10,$20,$40,$00,$70,$88,$10,$20,$20,$00,$20,$00
  .byte $70,$88,$A8,$B8,$B0,$80,$78,$00,$20,$50,$88,$88,$F8,$88,$88,$00
  .byte $F0,$88,$88,$F0,$88,$88,$F0,$00,$70,$88,$80,$80,$80,$88,$70,$00
  .byte $F0,$88,$88,$88,$88,$88,$F0,$00,$F8,$80,$80,$F0,$80,$80,$F8,$00
  .byte $F8,$80,$80,$F0,$80,$80,$80,$00,$78,$80,$80,$80,$98,$88,$78,$00
  .byte $88,$88,$88,$F8,$88,$88,$88,$00,$70,$20,$20,$20,$20,$20,$70,$00
  .byte $08,$08,$08,$08,$08,$88,$70,$00,$88,$90,$A0,$C0,$A0,$90,$88,$00
  .byte $80,$80,$80,$80,$80,$80,$F8,$00,$88,$D8,$A8,$A8,$88,$88,$88,$00
  .byte $88,$88,$C8,$A8,$98,$88,$88,$00,$70,$88,$88,$88,$88,$88,$70,$00
  .byte $F0,$88,$88,$F0,$80,$80,$80,$00,$70,$88,$88,$88,$A8,$90,$68,$00
  .byte $F0,$88,$88,$F0,$A0,$90,$88,$00,$70,$88,$80,$70,$08,$88,$70,$00
  .byte $F8,$20,$20,$20,$20,$20,$20,$00,$88,$88,$88,$88,$88,$88,$70,$00
  .byte $88,$88,$88,$88,$50,$50,$20,$00,$88,$88,$88,$A8,$A8,$D8,$88,$00
  .byte $88,$88,$50,$20,$50,$88,$88,$00,$88,$88,$50,$20,$20,$20,$20,$00
  .byte $F8,$08,$10,$20,$40,$80,$F8,$00,$F8,$C0,$C0,$C0,$C0,$C0,$F8,$00
  .byte $00,$80,$40,$20,$10,$08,$00,$00,$F8,$18,$18,$18,$18,$18,$F8,$00
  .byte $00,$00,$20,$50,$88,$00,$00,$00,$00,$00,$00,$00,$00,$00,$F8,$00

HUD_PAT:
  .byte $00,$FF,$00,$00,$00,$00,$FF,$00,$00,$FF,$01,$01,$01,$01,$FF,$00
  .byte $00,$FF,$03,$03,$03,$03,$FF,$00,$00,$FF,$07,$07,$07,$07,$FF,$00
  .byte $00,$FF,$0F,$0F,$0F,$0F,$FF,$00,$00,$FF,$1F,$1F,$1F,$1F,$FF,$00
  .byte $00,$FF,$3F,$3F,$3F,$3F,$FF,$00,$00,$FF,$7F,$7F,$7F,$7F,$FF,$00
  .byte $00,$FF,$FF,$FF,$FF,$FF,$FF,$00,$00,$FF,$00,$00,$00,$00,$FF,$00
  .byte $00,$FF,$80,$80,$80,$80,$FF,$00,$00,$FF,$C0,$C0,$C0,$C0,$FF,$00
  .byte $00,$FF,$E0,$E0,$E0,$E0,$FF,$00,$00,$FF,$F0,$F0,$F0,$F0,$FF,$00
  .byte $00,$FF,$F8,$F8,$F8,$F8,$FF,$00,$00,$FF,$FC,$FC,$FC,$FC,$FF,$00
  .byte $00,$FF,$FE,$FE,$FE,$FE,$FF,$00,$00,$FF,$FF,$FF,$FF,$FF,$FF,$00
  .byte $00,$FF,$00,$00,$00,$00,$FF,$00,$00,$FF,$80,$80,$80,$80,$FF,$00
  .byte $00,$FF,$C0,$C0,$C0,$C0,$FF,$00,$00,$FF,$E0,$E0,$E0,$E0,$FF,$00
  .byte $00,$FF,$F0,$F0,$F0,$F0,$FF,$00,$00,$FF,$F8,$F8,$F8,$F8,$FF,$00
  .byte $00,$FF,$FC,$FC,$FC,$FC,$FF,$00,$00,$FF,$FE,$FE,$FE,$FE,$FF,$00
  .byte $00,$FF,$FF,$FF,$FF,$FF,$FF,$00,$3C,$7E,$FF,$FF,$FF,$FF,$7E,$3C
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00

HUD_COL:
  .byte $11,$F1,$B6,$B6,$B6,$B6,$F1,$11,$11,$F1,$B6,$B6,$B6,$B6,$F1,$11
  .byte $11,$F1,$B6,$B6,$B6,$B6,$F1,$11,$11,$F1,$B6,$B6,$B6,$B6,$F1,$11
  .byte $11,$F1,$B6,$B6,$B6,$B6,$F1,$11,$11,$F1,$B6,$B6,$B6,$B6,$F1,$11
  .byte $11,$F1,$B6,$B6,$B6,$B6,$F1,$11,$11,$F1,$B6,$B6,$B6,$B6,$F1,$11
  .byte $11,$F1,$B6,$B6,$B6,$B6,$F1,$11,$11,$F1,$B6,$B6,$B6,$B6,$F1,$11
  .byte $11,$F1,$B6,$B6,$B6,$B6,$F1,$11,$11,$F1,$B6,$B6,$B6,$B6,$F1,$11
  .byte $11,$F1,$B6,$B6,$B6,$B6,$F1,$11,$11,$F1,$B6,$B6,$B6,$B6,$F1,$11
  .byte $11,$F1,$B6,$B6,$B6,$B6,$F1,$11,$11,$F1,$B6,$B6,$B6,$B6,$F1,$11
  .byte $11,$F1,$B6,$B6,$B6,$B6,$F1,$11,$11,$F1,$B6,$B6,$B6,$B6,$F1,$11
  .byte $11,$F1,$74,$74,$74,$74,$F1,$11,$11,$F1,$74,$74,$74,$74,$F1,$11
  .byte $11,$F1,$74,$74,$74,$74,$F1,$11,$11,$F1,$74,$74,$74,$74,$F1,$11
  .byte $11,$F1,$74,$74,$74,$74,$F1,$11,$11,$F1,$74,$74,$74,$74,$F1,$11
  .byte $11,$F1,$74,$74,$74,$74,$F1,$11,$11,$F1,$74,$74,$74,$74,$F1,$11
  .byte $11,$F1,$74,$74,$74,$74,$F1,$11,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1
  .byte $11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11
  .byte $11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11

SPR_DATA:
  .byte $00,$00,$01,$03,$07,$03,$03,$1F,$3F,$3F,$37,$37,$1B,$0F,$0F,$0F
  .byte $00,$00,$E0,$B0,$F0,$AC,$DE,$CC,$CC,$7C,$F8,$C0,$60,$C0,$C0,$C0
  .byte $00,$00,$01,$03,$07,$03,$03,$1F,$3F,$3F,$37,$37,$1B,$0F,$0F,$0F
  .byte $00,$00,$E0,$B0,$F0,$AC,$DE,$FC,$FE,$7E,$C0,$C0,$40,$C0,$C0,$C0
  .byte $00,$00,$07,$0E,$1F,$0E,$0F,$3F,$7F,$7E,$6F,$6F,$36,$1F,$0F,$0F
  .byte $00,$00,$80,$C0,$C0,$B0,$78,$30,$30,$F0,$E0,$80,$C0,$C0,$C0,$C0
  .byte $00,$00,$00,$01,$03,$07,$03,$03,$1F,$3F,$3F,$37,$17,$0F,$0F,$0F
  .byte $60,$60,$60,$E0,$B0,$F0,$A0,$C0,$E0,$E0,$60,$F0,$B0,$E0,$C0,$C0
  .byte $00,$00,$1F,$37,$3F,$1C,$0F,$3F,$7F,$DF,$DF,$1B,$1D,$1F,$0F,$0F
  .byte $00,$00,$00,$80,$80,$80,$00,$C0,$E0,$70,$D8,$D8,$C0,$C0,$C0,$C0
  .byte $00,$00,$01,$03,$07,$03,$03,$1F,$3F,$3F,$37,$37,$1B,$0F,$0F,$0F
  .byte $00,$00,$EC,$AC,$EC,$AC,$DC,$D8,$F0,$E0,$E0,$80,$40,$C0,$C0,$C0
  .byte $00,$00,$01,$03,$07,$03,$03,$1F,$3F,$3F,$37,$37,$1B,$0F,$0F,$0F
  .byte $00,$00,$E0,$B0,$F0,$A0,$CC,$FE,$F6,$FE,$FE,$CC,$40,$C0,$C0,$C0
  .byte $00,$00,$00,$01,$03,$07,$03,$03,$1F,$3F,$3F,$37,$17,$0F,$0F,$0F
  .byte $30,$30,$30,$F0,$B0,$F0,$A0,$C0,$C0,$C0,$40,$E0,$70,$E0,$C0,$C0
  .byte $00,$00,$0F,$1B,$1F,$6B,$F7,$67,$67,$7D,$3F,$07,$0D,$07,$07,$07
  .byte $00,$00,$00,$80,$C0,$80,$80,$F0,$F8,$F8,$D8,$D8,$B0,$E0,$E0,$E0
  .byte $00,$00,$0F,$1B,$1F,$6B,$F7,$7F,$FF,$FD,$07,$07,$05,$07,$07,$07
  .byte $00,$00,$00,$80,$C0,$80,$80,$F0,$F8,$F8,$D8,$D8,$B0,$E0,$E0,$E0
  .byte $00,$00,$03,$06,$07,$1A,$3D,$19,$19,$1E,$0F,$03,$06,$07,$07,$07
  .byte $00,$00,$C0,$E0,$F0,$E0,$E0,$F8,$FC,$FC,$EC,$EC,$D8,$F0,$E0,$E0
  .byte $0C,$0C,$0C,$0F,$1B,$1F,$0B,$07,$0F,$0F,$0D,$1F,$1B,$0F,$07,$07
  .byte $00,$00,$00,$00,$80,$C0,$80,$80,$F0,$F8,$F8,$D8,$D0,$E0,$E0,$E0
  .byte $00,$00,$01,$03,$03,$02,$01,$07,$0F,$1D,$37,$37,$07,$07,$07,$07
  .byte $00,$00,$F0,$D8,$F8,$70,$E0,$F8,$FC,$F6,$F6,$B0,$70,$F0,$E0,$E0
  .byte $00,$00,$6F,$6B,$6F,$6B,$77,$37,$1F,$0F,$0F,$03,$05,$07,$07,$07
  .byte $00,$00,$00,$80,$C0,$80,$80,$F0,$F8,$F8,$D8,$D8,$B0,$E0,$E0,$E0
  .byte $00,$00,$0F,$1B,$1F,$0B,$67,$FF,$DF,$FF,$FF,$67,$05,$07,$07,$07
  .byte $00,$00,$00,$80,$C0,$80,$80,$F0,$F8,$F8,$D8,$D8,$B0,$E0,$E0,$E0
  .byte $18,$18,$18,$1F,$1B,$1F,$0B,$07,$07,$07,$05,$0F,$1D,$0F,$07,$07
  .byte $00,$00,$00,$00,$80,$C0,$80,$80,$F0,$F8,$F8,$D8,$D0,$E0,$E0,$E0
  .byte $00,$0F,$1F,$1F,$3C,$38,$38,$70,$70,$70,$70,$70,$70,$00,$00,$00
  .byte $00,$C0,$E0,$E0,$F0,$70,$70,$38,$38,$38,$1C,$1C,$1C,$00,$00,$00
  .byte $00,$0F,$0F,$1F,$1C,$1C,$1C,$38,$38,$38,$38,$38,$38,$00,$00,$00
  .byte $00,$C0,$C0,$E0,$E0,$70,$70,$38,$38,$38,$1C,$1C,$1C,$00,$00,$00
  .byte $00,$1F,$1F,$1F,$1E,$0E,$0E,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$E0,$FC,$FC,$3C,$1C,$1C,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$1F,$1F,$1F,$1E,$1C,$1C,$1C,$38,$38,$38,$38,$38,$00,$00,$00
  .byte $00,$F8,$F8,$F8,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$07,$0F,$0F,$1E,$1C,$1C,$38,$38,$38,$70,$70,$70,$00,$00,$00
  .byte $00,$E0,$F0,$F0,$78,$38,$38,$1C,$1C,$1C,$1C,$1C,$1C,$00,$00,$00
  .byte $00,$07,$07,$0F,$0E,$1C,$1C,$38,$38,$38,$70,$70,$70,$00,$00,$00
  .byte $00,$E0,$E0,$F0,$70,$70,$70,$38,$38,$38,$38,$38,$38,$00,$00,$00
  .byte $00,$0F,$7F,$7F,$78,$70,$70,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$F0,$F0,$F0,$F0,$E0,$E0,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$3F,$3F,$3F,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$F0,$F0,$F0,$F0,$70,$70,$70,$38,$38,$38,$38,$38,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$0C,$0E,$03,$0F,$0F,$01,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$0E,$FF,$FF,$FF,$FF,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$DF,$DF,$DF,$9F,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$F8,$F8,$FC,$F8,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$1F,$1F,$3F,$1F,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$FB,$FB,$FB,$F9,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$70,$FF,$FF,$FF,$FF,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$30,$70,$C0,$F0,$F0,$80,$00
  .byte $00,$0D,$73,$1F,$1F,$73,$0D,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $F0,$F8,$FC,$FC,$FC,$FC,$F8,$F0,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $1E,$3F,$7F,$7F,$7F,$7F,$3F,$1E,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$60,$9C,$F0,$F0,$9C,$60,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$06,$0F,$39,$E0,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$18,$BC,$E6,$42,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$31,$7B,$CE,$84,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$C0,$E0,$38,$0E,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$01,$11,$09,$07,$07,$3F,$07,$07,$09,$11,$01,$00,$00,$00
  .byte $00,$00,$00,$10,$20,$C0,$C0,$F8,$C0,$C0,$20,$10,$00,$00,$00,$00
  .byte $80,$E0,$F8,$FE,$F8,$E0,$80,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $02,$0E,$3E,$FE,$3E,$0E,$02,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $07,$0F,$0F,$0F,$0F,$07,$03,$1F,$3F,$3F,$3F,$3F,$3F,$1F,$0F,$0F
  .byte $E0,$F8,$F8,$F8,$F8,$FE,$FF,$FF,$FE,$FE,$FE,$FC,$F0,$F0,$E0,$E0
  .byte $07,$0F,$0F,$0F,$0F,$07,$03,$1F,$3F,$3F,$3F,$3F,$3F,$1F,$0F,$0F
  .byte $E0,$F8,$F8,$F8,$F8,$FE,$FF,$FF,$FF,$FF,$FF,$E0,$E0,$E0,$E0,$E0
  .byte $1F,$3F,$3F,$3F,$3F,$1F,$0F,$3F,$7F,$7F,$7F,$7F,$7F,$3F,$1F,$0F
  .byte $80,$E0,$E0,$E0,$E0,$F8,$FC,$FC,$F8,$F8,$F8,$F0,$E0,$E0,$E0,$E0
  .byte $00,$07,$0F,$0F,$0F,$0F,$07,$03,$1F,$3F,$3F,$3F,$3F,$1F,$0F,$0F
  .byte $70,$F0,$F0,$F0,$F8,$F8,$F8,$F0,$F0,$F0,$F0,$F8,$F8,$F8,$F0,$E0
  .byte $7E,$FF,$FF,$FF,$7F,$3F,$1F,$3F,$7F,$FF,$FF,$FF,$1F,$1F,$1F,$0F
  .byte $00,$80,$80,$C0,$C0,$C0,$C0,$E0,$F0,$F8,$FC,$FC,$FC,$E0,$E0,$E0
  .byte $07,$0F,$0F,$0F,$0F,$07,$03,$1F,$3F,$3F,$3F,$3F,$3F,$1F,$0F,$0F
  .byte $E0,$F8,$FE,$FE,$FE,$FE,$FE,$FE,$FC,$F8,$F0,$F0,$E0,$E0,$E0,$E0
  .byte $07,$0F,$0F,$0F,$0F,$07,$03,$1F,$3F,$3F,$3F,$3F,$3F,$1F,$0F,$0F
  .byte $E0,$F8,$F8,$F8,$F8,$F8,$FE,$FF,$FF,$FF,$FF,$FF,$EE,$E0,$E0,$E0
  .byte $00,$07,$0F,$0F,$0F,$0F,$07,$03,$1F,$3F,$3F,$3F,$3F,$1F,$0F,$0F
  .byte $38,$F8,$F8,$F8,$F8,$F8,$F8,$F0,$E0,$E0,$E0,$F0,$F8,$F8,$F0,$E0
  .byte $07,$1F,$1F,$1F,$1F,$7F,$FF,$FF,$7F,$7F,$7F,$3F,$0F,$0F,$07,$07
  .byte $E0,$F0,$F0,$F0,$F0,$E0,$C0,$F8,$FC,$FC,$FC,$FC,$FC,$F8,$F0,$F0
  .byte $07,$1F,$1F,$1F,$1F,$7F,$FF,$FF,$FF,$FF,$FF,$07,$07,$07,$07,$07
  .byte $E0,$F0,$F0,$F0,$F0,$E0,$C0,$F8,$FC,$FC,$FC,$FC,$FC,$F8,$F0,$F0
  .byte $01,$07,$07,$07,$07,$1F,$3F,$3F,$1F,$1F,$1F,$0F,$07,$07,$07,$07
  .byte $F8,$FC,$FC,$FC,$FC,$F8,$F0,$FC,$FE,$FE,$FE,$FE,$FE,$FC,$F8,$F0
  .byte $0E,$0F,$0F,$0F,$1F,$1F,$1F,$0F,$0F,$0F,$0F,$1F,$1F,$1F,$0F,$07
  .byte $00,$E0,$F0,$F0,$F0,$F0,$E0,$C0,$F8,$FC,$FC,$FC,$FC,$F8,$F0,$F0
  .byte $00,$01,$01,$03,$03,$03,$03,$07,$0F,$1F,$3F,$3F,$3F,$07,$07,$07
  .byte $7E,$FF,$FF,$FF,$FE,$FC,$F8,$FC,$FE,$FF,$FF,$FF,$F8,$F8,$F8,$F0
  .byte $07,$1F,$7F,$7F,$7F,$7F,$7F,$7F,$3F,$1F,$0F,$0F,$07,$07,$07,$07
  .byte $E0,$F0,$F0,$F0,$F0,$E0,$C0,$F8,$FC,$FC,$FC,$FC,$FC,$F8,$F0,$F0
  .byte $07,$1F,$1F,$1F,$1F,$1F,$7F,$FF,$FF,$FF,$FF,$FF,$77,$07,$07,$07
  .byte $E0,$F0,$F0,$F0,$F0,$E0,$C0,$F8,$FC,$FC,$FC,$FC,$FC,$F8,$F0,$F0
  .byte $1C,$1F,$1F,$1F,$1F,$1F,$1F,$0F,$07,$07,$07,$0F,$1F,$1F,$0F,$07
  .byte $00,$E0,$F0,$F0,$F0,$F0,$E0,$C0,$F8,$FC,$FC,$FC,$FC,$F8,$F0,$F0
  .byte $0F,$0F,$1F,$1F,$3F,$3E,$3C,$7C,$78,$78,$78,$78,$78,$78,$F8,$F8
  .byte $E0,$E0,$F0,$F0,$F8,$F8,$78,$7C,$3C,$3C,$3E,$1E,$1E,$1E,$1F,$1F
  .byte $0F,$0F,$0F,$1F,$1F,$1E,$1E,$3E,$3C,$3C,$3C,$3C,$3C,$3C,$7C,$7C
  .byte $E0,$E0,$E0,$F0,$F0,$F8,$78,$7C,$3C,$3C,$3E,$1E,$1E,$1E,$1F,$1F
  .byte $0F,$1F,$1F,$1F,$1F,$1F,$0F,$1F,$3E,$3E,$00,$00,$00,$00,$00,$00
  .byte $E0,$F0,$FE,$FE,$FE,$3E,$1E,$1E,$3E,$3E,$00,$00,$00,$00,$00,$00
  .byte $0F,$1F,$1F,$1F,$1F,$1F,$1E,$1E,$3E,$3C,$3C,$3C,$3C,$3C,$7E,$7E
  .byte $E0,$FE,$FF,$FF,$FF,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $07,$07,$0F,$0F,$1F,$1F,$1E,$3E,$3C,$3C,$7C,$78,$78,$78,$F8,$F8
  .byte $F0,$F0,$F8,$F8,$FC,$7C,$3C,$3E,$1E,$1E,$1E,$1E,$1E,$1E,$1F,$1F
  .byte $07,$07,$07,$0F,$0F,$1F,$1E,$3E,$3C,$3C,$7C,$78,$78,$78,$F8,$F8
  .byte $F0,$F0,$F0,$F8,$F8,$78,$78,$7C,$3C,$3C,$3C,$3C,$3C,$3C,$3E,$3E
  .byte $07,$0F,$7F,$7F,$7F,$7C,$78,$78,$7C,$7C,$00,$00,$00,$00,$00,$00
  .byte $F0,$F8,$F8,$F8,$F8,$F8,$F0,$F8,$7C,$7C,$00,$00,$00,$00,$00,$00
  .byte $07,$7F,$FF,$FF,$FF,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $F0,$F8,$F8,$F8,$F8,$F8,$78,$78,$7C,$3C,$3C,$3C,$3C,$3C,$7E,$7E
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$0E,$3F,$7F,$7F,$7F,$7F,$39
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$0F,$FF,$FF,$FF,$FF,$FF
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$FF,$FF,$FF,$FF,$FF
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$03,$FF,$FF,$FF,$FF,$FC
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$60,$7F,$7F,$7F,$7F,$1F
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$FF,$FF,$FF,$FF,$FF
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$78,$FF,$FF,$FF,$FF,$FF
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$38,$7E,$FF,$FF,$FF,$FF,$CE

SPR_END:

PER_LO:
  .byte $00,$BC,$86,$53,$24,$F6,$CC,$A4,$7E,$5A,$38,$18,$FA,$DE,$C3,$AA
  .byte $92,$7B,$66,$52,$3F,$2D,$1C,$0C,$FD,$EF,$E1,$D5,$C9,$BE,$B3,$A9
  .byte $9F,$96,$8E,$86,$7F,$77,$71,$6A,$64,$5F,$59,$54,$50,$4B,$47,$43
  .byte $3F,$3C,$38,$35,$32,$2F,$2D,$2A,$28,$26,$24,$22,$20

PER_HI:
  .byte $00,$03,$03,$03,$03,$02,$02,$02,$02,$02,$02,$02,$01,$01,$01,$01
  .byte $01,$01,$01,$01,$01,$01,$01,$01,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00

S0V0:
  .byte $22,$08,$22,$08,$25,$08,$29,$08,$2E,$10,$2C,$08,$29,$08,$27,$08
  .byte $27,$08,$2A,$08,$2E,$08,$2C,$10,$29,$10,$25,$08,$25,$08,$29,$08
  .byte $2C,$08,$2A,$10,$29,$08,$27,$08,$29,$18,$25,$08,$27,$10,$29,$10
  .byte $2E,$08,$2E,$08,$2C,$08,$29,$08,$31,$10,$30,$08,$2C,$08,$2A,$08
  .byte $2A,$08,$2E,$08,$31,$08,$30,$10,$2C,$10,$29,$08,$29,$08,$2C,$08
  .byte $30,$08,$2E,$10,$2C,$08,$29,$08,$2E,$20,$00,$08,$22,$08,$25,$08
  .byte $29,$08,$FE,$00

S0V1:
  .byte $0A,$08,$0A,$08,$16,$08,$0A,$08,$0A,$08,$0A,$08,$16,$08,$0A,$08
  .byte $0A,$08,$0A,$08,$16,$08,$0A,$08,$0A,$08,$0A,$08,$16,$08,$0A,$08
  .byte $06,$08,$06,$08,$12,$08,$06,$08,$06,$08,$06,$08,$12,$08,$06,$08
  .byte $08,$08,$08,$08,$14,$08,$08,$08,$08,$08,$08,$08,$14,$08,$08,$08
  .byte $0A,$08,$0A,$08,$16,$08,$0A,$08,$0A,$08,$0A,$08,$16,$08,$0A,$08
  .byte $06,$08,$06,$08,$12,$08,$06,$08,$06,$08,$06,$08,$12,$08,$06,$08
  .byte $05,$08,$05,$08,$11,$08,$05,$08,$05,$08,$05,$08,$11,$08,$05,$08
  .byte $0A,$08,$0A,$08,$16,$08,$0A,$08,$0A,$08,$0A,$08,$16,$08,$0A,$08
  .byte $FE,$00

S0V2:
  .byte $16,$04,$19,$04,$1D,$04,$19,$04,$16,$04,$19,$04,$1D,$04,$19,$04
  .byte $16,$04,$19,$04,$1D,$04,$19,$04,$16,$04,$19,$04,$1D,$04,$19,$04
  .byte $16,$04,$19,$04,$1D,$04,$19,$04,$16,$04,$19,$04,$1D,$04,$19,$04
  .byte $16,$04,$19,$04,$1D,$04,$19,$04,$16,$04,$19,$04,$1D,$04,$19,$04
  .byte $12,$04,$16,$04,$19,$04,$16,$04,$12,$04,$16,$04,$19,$04,$16,$04
  .byte $12,$04,$16,$04,$19,$04,$16,$04,$12,$04,$16,$04,$19,$04,$16,$04
  .byte $14,$04,$18,$04,$1B,$04,$18,$04,$14,$04,$18,$04,$1B,$04,$18,$04
  .byte $14,$04,$18,$04,$1B,$04,$18,$04,$14,$04,$18,$04,$1B,$04,$18,$04
  .byte $16,$04,$19,$04,$1D,$04,$19,$04,$16,$04,$19,$04,$1D,$04,$19,$04
  .byte $16,$04,$19,$04,$1D,$04,$19,$04,$16,$04,$19,$04,$1D,$04,$19,$04
  .byte $12,$04,$16,$04,$19,$04,$16,$04,$12,$04,$16,$04,$19,$04,$16,$04
  .byte $12,$04,$16,$04,$19,$04,$16,$04,$12,$04,$16,$04,$19,$04,$16,$04
  .byte $11,$04,$15,$04,$18,$04,$15,$04,$11,$04,$15,$04,$18,$04,$15,$04
  .byte $11,$04,$15,$04,$18,$04,$15,$04,$11,$04,$15,$04,$18,$04,$15,$04
  .byte $16,$04,$19,$04,$1D,$04,$19,$04,$16,$04,$19,$04,$1D,$04,$19,$04
  .byte $16,$04,$19,$04,$1D,$04,$19,$04,$16,$04,$19,$04,$1D,$04,$19,$04
  .byte $FE,$00

S1V0:
  .byte $1D,$06,$20,$06,$25,$06,$29,$06,$2C,$0A,$29,$06,$2C,$06,$31,$18
  .byte $FF

S1V1:
  .byte $0D,$0C,$0D,$0C,$08,$0C,$0D,$18,$FF

S1V2:
  .byte $19,$06,$1D,$06,$20,$06,$25,$06,$1D,$06,$20,$06,$25,$06,$29,$06
  .byte $1D,$18,$FF

S2V0:
  .byte $20,$08,$20,$08,$20,$08,$25,$18,$29,$08,$29,$08,$29,$08,$2C,$18
  .byte $2E,$10,$2C,$08,$29,$08,$25,$10,$27,$10,$25,$20,$00,$10,$25,$08
  .byte $29,$08,$2C,$08,$31,$18,$30,$08,$2C,$08,$2E,$08,$30,$18,$31,$10
  .byte $2C,$10,$29,$10,$2C,$10,$31,$30,$00,$60,$FE,$00

S2V1:
  .byte $0D,$08,$0D,$08,$19,$08,$0D,$08,$0D,$08,$0D,$08,$19,$08,$0D,$08
  .byte $0D,$08,$0D,$08,$19,$08,$0D,$08,$0D,$08,$0D,$08,$19,$08,$0D,$08
  .byte $06,$08,$06,$08,$12,$08,$06,$08,$06,$08,$06,$08,$12,$08,$06,$08
  .byte $08,$08,$08,$08,$14,$08,$08,$08,$08,$08,$08,$08,$14,$08,$08,$08
  .byte $0D,$08,$0D,$08,$19,$08,$0D,$08,$0D,$08,$0D,$08,$19,$08,$0D,$08
  .byte $06,$08,$06,$08,$12,$08,$06,$08,$06,$08,$06,$08,$12,$08,$06,$08
  .byte $08,$08,$08,$08,$14,$08,$08,$08,$08,$08,$08,$08,$14,$08,$08,$08
  .byte $0D,$08,$0D,$08,$19,$08,$0D,$08,$0D,$08,$0D,$08,$19,$08,$0D,$08
  .byte $FE,$00

S2V2:
  .byte $19,$04,$1D,$04,$20,$04,$1D,$04,$19,$04,$1D,$04,$20,$04,$1D,$04
  .byte $19,$04,$1D,$04,$20,$04,$1D,$04,$19,$04,$1D,$04,$20,$04,$1D,$04
  .byte $19,$04,$1D,$04,$20,$04,$1D,$04,$19,$04,$1D,$04,$20,$04,$1D,$04
  .byte $19,$04,$1D,$04,$20,$04,$1D,$04,$19,$04,$1D,$04,$20,$04,$1D,$04
  .byte $16,$04,$19,$04,$1E,$04,$19,$04,$16,$04,$19,$04,$1E,$04,$19,$04
  .byte $16,$04,$19,$04,$1E,$04,$19,$04,$16,$04,$19,$04,$1E,$04,$19,$04
  .byte $18,$04,$1B,$04,$20,$04,$1B,$04,$18,$04,$1B,$04,$20,$04,$1B,$04
  .byte $18,$04,$1B,$04,$20,$04,$1B,$04,$18,$04,$1B,$04,$20,$04,$1B,$04
  .byte $19,$04,$1D,$04,$20,$04,$1D,$04,$19,$04,$1D,$04,$20,$04,$1D,$04
  .byte $19,$04,$1D,$04,$20,$04,$1D,$04,$19,$04,$1D,$04,$20,$04,$1D,$04
  .byte $16,$04,$19,$04,$1E,$04,$19,$04,$16,$04,$19,$04,$1E,$04,$19,$04
  .byte $16,$04,$19,$04,$1E,$04,$19,$04,$16,$04,$19,$04,$1E,$04,$19,$04
  .byte $18,$04,$1B,$04,$20,$04,$1B,$04,$18,$04,$1B,$04,$20,$04,$1B,$04
  .byte $18,$04,$1B,$04,$20,$04,$1B,$04,$18,$04,$1B,$04,$20,$04,$1B,$04
  .byte $19,$04,$1D,$04,$20,$04,$25,$04,$19,$04,$1D,$04,$20,$04,$25,$04
  .byte $19,$04,$1D,$04,$20,$04,$25,$04,$19,$04,$1D,$04,$20,$04,$25,$04
  .byte $FE,$00

SONG_TAB:
  .byte <S0V0,>S0V0,<S0V1,>S0V1,<S0V2,>S0V2,<S1V0,>S1V0,<S1V1,>S1V1,<S1V2,>S1V2,<S2V0,>S2V0,<S2V1,>S2V1,<S2V2,>S2V2

END_MARK:
  .byte $FF,$FF

SFX_TAB:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$08,$02,$0A,$08,$0D,$0F,$0A,$00
  .byte $BC,$02,$0E,$0D,$0F,$0F,$0E,$00,$6E,$00,$00,$03,$09,$08,$05,$00
  .byte $2C,$01,$F8,$0A,$05,$07,$08,$00,$A4,$01,$F7,$00,$09,$00,$0A,$00
  .byte $C8,$00,$0C,$14,$0F,$0F,$28,$00,$A0,$00,$04,$06,$0E,$0C,$1E,$01
  .byte $08,$02,$F2,$03,$0F,$0A,$16,$00,$78,$00,$09,$05,$0F,$0C,$1A,$00
  .byte $E8,$03,$02,$18,$0F,$0F,$22,$01,$5A,$00,$00,$02,$0F,$0D,$1C,$01
  .byte $04,$01,$F6,$00,$0C,$00,$0C,$00,$B4,$00,$EE,$00,$0B,$00,$09,$00

VSTART:
  .byte $0D,$00,$0B,$00,$08

PAT0:   ; TITLE
  .byte $86,$00,$01,$80,$86,$00,$01,$10,$86,$00,$01,$02,$89,$00,$01,$08
  .byte $86,$00,$02,$01,$20,$85,$00,$02,$FF,$FF,$84,$00,$0C,$FF,$FF,$00
  .byte $00,$47,$07,$07,$00,$FF,$FF,$00,$00,$81,$FF,$05,$1C,$FF,$FF,$00
  .byte $00,$81,$F0,$05,$00,$FF,$FF,$00,$00,$82,$07,$02,$FF,$FF,$81,$00
  .byte $07,$08,$00,$00,$FF,$FF,$00,$00,$82,$70,$04,$FF,$FF,$00,$00,$81
  .byte $FF,$87,$00,$86,$1C,$86,$07,$83,$00,$81,$FF,$83,$70,$81,$F0,$83
  .byte $00,$81,$80,$02,$00,$20,$86,$00,$01,$04,$83,$00,$86,$70,$84,$00
  .byte $02,$FF,$FF,$84,$00,$02,$F0,$F0,$81,$00,$01,$80,$82,$00,$01,$1C
  .byte $85,$00,$01,$07,$8C,$00,$02,$02,$70,$85,$00,$01,$FF,$FF,$00,$FF
  .byte $00,$FF,$00,$FF,$00,$89,$00,$01,$F0,$FF,$00,$FF,$00,$FF,$00,$FF
  .byte $00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FC,$00,$86,$E0,$81
  .byte $0E,$83,$0F,$81,$00,$83,$C0,$81,$03,$81,$1C,$02,$E3,$E3,$81,$80
  .byte $81,$70,$02,$8E,$8E,$81,$FF,$83,$E0,$81,$F0,$81,$0E,$02,$0F,$0F
  .byte $84,$00,$02,$C0,$C0,$81,$1F,$83,$03,$81,$F0,$81,$FE,$02,$F0,$F0
  .byte $81,$1F,$81,$E3,$02,$E0,$E0,$83,$00,$03,$40,$C0,$C0,$81,$F0,$81
  .byte $0E,$03,$01,$01,$E0,$84,$E3,$02,$FC,$0F,$81,$8F,$81,$8E,$01,$7F
  .byte $86,$C0,$01,$E3,$81,$E0,$81,$FF,$02,$E0,$8E,$81,$0F,$81,$FE,$02
  .byte $0E,$00,$85,$C0,$01,$E0,$81,$FF,$81,$E3,$02,$E0,$0F,$81,$F1,$81
  .byte $FE,$01,$70,$82,$C0,$82,$00,$86,$03,$86,$F0,$86,$E0,$86,$0F,$01
  .byte $E0,$81,$1F,$81,$03,$02,$E0,$01,$81,$F0,$81,$0E,$02,$0F,$C0,$84
  .byte $00,$03,$C0,$FC,$FC,$81,$E0,$81,$1C,$FF,$00,$FF,$00,$FF,$00,$FB
  .byte $00,$02,$7F,$7F,$81,$8F,$81,$01,$83,$E0,$81,$1C,$02,$0E,$0E,$81
  .byte $0F,$81,$01,$02,$70,$70,$81,$0E,$81,$01,$83,$00,$81,$C0,$02,$03
  .byte $03,$81,$1F,$81,$03,$83,$F0,$81,$FE,$02,$E0,$E0,$81,$1F,$81,$03
  .byte $02,$0F,$0F,$81,$F1,$81,$FE,$05,$C0,$C0,$E0,$C0,$C0,$81,$00,$02
  .byte $E0,$E0,$81,$1F,$81,$03,$83,$C0,$8B,$00,$01,$08,$89,$00,$01,$20
  .byte $86,$00,$01,$04,$83,$00,$01,$40,$83,$00,$01,$10,$86,$00,$01,$02
  .byte $FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00
  .byte $EB,$00,$01,$20,$86,$00,$01,$04,$83,$00,$01,$01,$FF,$00,$FF,$00
  .byte $FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00
  .byte $FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$D5,$00,$00

COL0:   ; TITLE
  .byte $86,$00,$01,$F1,$86,$11,$01,$F1,$86,$11,$01,$F1,$89,$11,$01,$F1
  .byte $86,$11,$02,$F1,$F1,$85,$11,$02,$66,$66,$84,$F1,$04,$66,$66,$F1
  .byte $F1,$81,$B1,$05,$F1,$66,$66,$F1,$F1,$81,$BB,$05,$B1,$66,$66,$F1
  .byte $F1,$81,$B1,$05,$F1,$66,$66,$F1,$F1,$82,$B1,$02,$66,$66,$84,$F1
  .byte $04,$66,$66,$F1,$F1,$82,$B1,$04,$66,$66,$F1,$F1,$81,$BB,$87,$F1
  .byte $8E,$B1,$83,$F1,$81,$BB,$86,$B1,$83,$F1,$81,$B1,$8E,$F1,$86,$B1
  .byte $84,$F1,$02,$BB,$BB,$84,$F1,$02,$B1,$B1,$86,$F1,$01,$B1,$85,$F1
  .byte $01,$B1,$8D,$F1,$01,$B1,$85,$F1,$01,$BB,$85,$F1,$FF,$00,$FF,$00
  .byte $FF,$00,$FB,$00,$02,$88,$88,$84,$11,$01,$B1,$85,$F1,$FF,$00,$FF
  .byte $00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$ED
  .byte $00,$86,$F1,$81,$B1,$83,$B6,$86,$B1,$81,$F1,$83,$61,$8E,$B1,$81
  .byte $BB,$83,$B6,$81,$B1,$81,$B6,$02,$B1,$B1,$84,$F1,$02,$61,$61,$89
  .byte $B1,$83,$61,$84,$B1,$02,$B6,$B6,$84,$F1,$02,$61,$61,$81,$B1,$81
  .byte $B6,$02,$61,$61,$85,$B6,$83,$B1,$81,$B6,$01,$B1,$86,$61,$01,$B1
  .byte $81,$B6,$81,$BB,$01,$B6,$82,$B1,$82,$B6,$01,$F1,$85,$61,$01,$B6
  .byte $81,$BB,$82,$B6,$82,$B1,$81,$61,$01,$B1,$82,$61,$82,$F1,$86,$B1
  .byte $86,$61,$86,$B6,$86,$B1,$01,$B6,$81,$B1,$81,$61,$02,$B1,$61,$81
  .byte $B1,$81,$B6,$02,$B1,$61,$84,$F1,$03,$61,$B1,$B1,$81,$B6,$81,$61
  .byte $FF,$00,$FF,$00,$FF,$00,$FB,$00,$83,$B1,$81,$61,$83,$B6,$81,$61
  .byte $02,$B6,$B6,$81,$B1,$81,$61,$83,$B1,$81,$61,$83,$F1,$81,$61,$83
  .byte $B1,$83,$61,$81,$B1,$81,$61,$02,$B6,$B6,$81,$B1,$81,$61,$83,$B1
  .byte $86,$61,$81,$F1,$83,$B1,$86,$61,$81,$F1,$02,$88,$88,$84,$11,$03
  .byte $88,$88,$F1,$89,$11,$01,$F1,$86,$11,$01,$F1,$83,$11,$01,$F1,$83
  .byte $11,$01,$F1,$86,$11,$01,$F1,$81,$11,$FF,$00,$FF,$00,$FF,$00,$FF
  .byte $00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$E6,$00,$03,$11,$11,$F1,$86
  .byte $11,$01,$F1,$83,$11,$01,$F1,$8A,$11,$02,$66,$66,$FF,$00,$FF,$00
  .byte $FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00
  .byte $FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$C7,$00,$00

NAM0:   ; TITLE
  .byte $01,$01,$81,$00,$01,$02,$81,$00,$01,$03,$99,$00,$01,$04,$81,$00
  .byte $01,$05,$A2,$00,$01,$06,$90,$00,$89,$07,$09,$08,$09,$0A,$0B,$0C
  .byte $0D,$0B,$0E,$0A,$8A,$07,$8A,$0F,$08,$10,$0F,$11,$12,$13,$11,$12
  .byte $14,$95,$0F,$0A,$15,$10,$0F,$11,$16,$17,$11,$18,$19,$1A,$95,$0F
  .byte $08,$1B,$0F,$1C,$1D,$1E,$1C,$1F,$61,$8A,$0F,$9E,$60,$82,$01,$18
  .byte $02,$03,$04,$05,$06,$01,$07,$08,$09,$07,$08,$09,$0A,$0B,$01,$0C
  .byte $08,$0D,$07,$08,$09,$0C,$0E,$09,$86,$01,$18,$0F,$10,$11,$12,$13
  .byte $14,$15,$16,$17,$15,$16,$17,$18,$19,$01,$1A,$1B,$11,$15,$16,$17
  .byte $1C,$1D,$1E,$86,$01,$18,$1F,$60,$11,$61,$62,$11,$61,$63,$64,$61
  .byte $63,$64,$65,$66,$01,$67,$68,$69,$61,$63,$64,$6A,$68,$6B,$82,$01
  .byte $9E,$00,$9D,$6C,$01,$6D,$99,$00,$01,$6E,$81,$00,$01,$6F,$A2,$00
  .byte $01,$70,$94,$00,$01,$71,$81,$00,$01,$72,$A2,$00,$01,$01,$81,$00
  .byte $01,$02,$94,$00,$01,$03,$FE,$00,$9E,$04,$9E,$00,$00

PAT1:   ; SELECT
  .byte $FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00
  .byte $FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00
  .byte $02,$00,$00,$84,$3F,$88,$00,$84,$FC,$86,$3F,$86,$00,$86,$FC,$FF
  .byte $00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF
  .byte $00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$C7,$00,$86
  .byte $3F,$86,$00,$86,$FC,$86,$00,$02,$3F,$3F,$8C,$00,$02,$FC,$FC,$FF
  .byte $00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF
  .byte $00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$A5,$00,$00

COL1:   ; SELECT
  .byte $FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00
  .byte $FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$F7,$00
  .byte $86,$F1,$02,$F4,$F4,$84,$74,$02,$F4,$F4,$84,$F7,$02,$F4,$F4,$8C
  .byte $74,$86,$F7,$86,$74,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF
  .byte $00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF
  .byte $00,$FF,$00,$B7,$00,$86,$F1,$86,$44,$86,$74,$86,$F7,$86,$74,$02
  .byte $F1,$F1,$82,$F6,$04,$F4,$F4,$74,$74,$82,$F6,$04,$F4,$F4,$F7,$F7
  .byte $82,$F6,$04,$F4,$F4,$74,$74,$82,$F6,$02,$F4,$F4,$FF,$00,$FF,$00
  .byte $FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00
  .byte $FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$9F,$00,$00

NAM1:   ; SELECT
  .byte $FF,$00,$FF,$00,$FC,$00,$03,$01,$01,$02,$82,$03,$01,$04,$8E,$01
  .byte $01,$02,$82,$03,$01,$04,$82,$01,$01,$05,$82,$06,$01,$07,$8E,$01
  .byte $01,$05,$82,$06,$01,$07,$82,$01,$01,$05,$82,$06,$01,$07,$8E,$01
  .byte $01,$05,$82,$06,$01,$07,$82,$01,$01,$05,$82,$06,$01,$07,$8E,$01
  .byte $01,$05,$82,$06,$01,$07,$82,$01,$01,$03,$82,$04,$01,$05,$8E,$01
  .byte $01,$03,$82,$04,$01,$05,$82,$01,$01,$03,$82,$04,$01,$05,$8E,$01
  .byte $01,$03,$82,$04,$01,$05,$82,$01,$01,$03,$82,$04,$01,$05,$8E,$01
  .byte $01,$03,$82,$04,$01,$05,$82,$01,$01,$03,$82,$04,$01,$05,$8E,$01
  .byte $01,$03,$82,$04,$01,$05,$82,$01,$01,$03,$82,$04,$01,$05,$8E,$01
  .byte $01,$03,$82,$04,$06,$05,$01,$01,$06,$06,$07,$82,$08,$01,$09,$8E
  .byte $06,$01,$07,$82,$08,$03,$09,$06,$06,$BE,$02,$00

PAT2:   ; ROOM
  .byte $BA,$00,$82,$F0,$82,$00,$82,$0F,$82,$00,$82,$03,$8A,$00,$82,$3F
  .byte $82,$00,$82,$30,$82,$00,$82,$0F,$8D,$00,$01,$3E,$86,$F0,$86,$0F
  .byte $86,$F0,$86,$0F,$86,$03,$86,$00,$86,$3F,$86,$30,$86,$0F,$02,$00
  .byte $00,$83,$01,$02,$00,$7F,$85,$00,$02,$F0,$70,$83,$F0,$01,$70,$FF
  .byte $00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF
  .byte $00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$B8,$00,$02,$7F,$3E
  .byte $84,$00,$86,$F0,$86,$0F,$A8,$00,$0E,$FC,$F0,$E0,$E0,$C0,$C0,$00
  .byte $00,$1F,$07,$03,$03,$01,$01,$81,$C0,$05,$E0,$E0,$F0,$FC,$00,$81
  .byte $01,$04,$03,$03,$07,$1F,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00
  .byte $FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00
  .byte $FF,$00,$FF,$00,$A1,$00,$85,$7F,$FF,$00,$FF,$00,$FF,$00,$FF,$00
  .byte $FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00
  .byte $FF,$00,$FF,$00,$FF,$00,$AF,$00,$00

COL2:   ; ROOM
  .byte $86,$00,$84,$66,$02,$AA,$AA,$84,$66,$02,$BB,$BB,$86,$AA,$86,$BB
  .byte $86,$88,$86,$66,$82,$AA,$82,$A8,$82,$BB,$82,$B8,$82,$AA,$82,$A4
  .byte $82,$BB,$82,$22,$82,$AA,$82,$DA,$82,$BB,$82,$B8,$82,$AA,$82,$A8
  .byte $8D,$77,$01,$B7,$8E,$76,$86,$A8,$86,$B8,$86,$A4,$86,$22,$86,$DA
  .byte $86,$B8,$86,$A8,$02,$77,$77,$83,$B7,$02,$77,$B7,$85,$BB,$02,$76
  .byte $76,$83,$B6,$01,$76,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF
  .byte $00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF
  .byte $00,$98,$00,$86,$AA,$86,$FF,$86,$88,$86,$77,$02,$B7,$B7,$84,$77
  .byte $8E,$76,$86,$BB,$86,$44,$88,$66,$84,$AA,$86,$DD,$02,$AA,$AA,$84
  .byte $A2,$02,$BB,$BB,$84,$B2,$85,$A2,$01,$AA,$85,$B2,$01,$BB,$84,$AA
  .byte $02,$FF,$FF,$84,$BB,$82,$FF,$84,$44,$FF,$00,$FF,$00,$FF,$00,$FF
  .byte $00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF
  .byte $00,$FF,$00,$FF,$00,$D8,$00,$86,$44,$86,$66,$8A,$AA,$82,$FF,$86
  .byte $88,$82,$FF,$82,$88,$01,$AA,$85,$EA,$01,$AA,$85,$EE,$01,$FF,$84
  .byte $22,$01,$FF,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF
  .byte $00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF
  .byte $00,$9F,$00,$00

NAM2:   ; ROOM
  .byte $DE,$00,$4D,$01,$02,$01,$02,$01,$02,$01,$02,$01,$02,$01,$02,$01
  .byte $02,$01,$02,$01,$02,$01,$02,$01,$02,$01,$02,$01,$02,$01,$02,$01
  .byte $02,$01,$02,$03,$04,$03,$04,$03,$04,$03,$04,$03,$04,$03,$04,$03
  .byte $04,$03,$04,$03,$04,$03,$04,$03,$04,$03,$04,$03,$04,$03,$04,$03
  .byte $04,$03,$04,$03,$04,$03,$04,$03,$04,$03,$04,$03,$04,$03,$05,$05
  .byte $84,$06,$45,$05,$05,$04,$03,$04,$07,$08,$09,$0A,$0B,$0C,$0D,$04
  .byte $03,$04,$03,$04,$03,$04,$03,$04,$03,$04,$03,$05,$05,$0E,$0F,$10
  .byte $11,$0E,$0E,$05,$05,$04,$03,$04,$12,$13,$14,$15,$16,$17,$18,$04
  .byte $03,$06,$03,$04,$03,$04,$03,$04,$03,$06,$03,$05,$05,$19,$1A,$1B
  .byte $11,$0E,$0E,$05,$05,$04,$03,$04,$85,$06,$02,$04,$01,$87,$02,$17
  .byte $01,$03,$03,$04,$05,$06,$07,$04,$04,$03,$03,$08,$01,$08,$01,$08
  .byte $01,$08,$01,$08,$01,$08,$01,$87,$09,$03,$01,$03,$03,$84,$0A,$65
  .byte $03,$03,$08,$01,$08,$01,$08,$01,$08,$01,$08,$01,$08,$01,$0A,$01
  .byte $08,$01,$08,$01,$08,$01,$0A,$0B,$03,$03,$04,$04,$06,$07,$04,$04
  .byte $03,$03,$08,$01,$08,$01,$0C,$0C,$08,$0D,$0E,$01,$08,$01,$0A,$01
  .byte $08,$01,$08,$01,$08,$01,$0A,$0B,$03,$03,$04,$04,$06,$07,$04,$04
  .byte $03,$03,$08,$01,$08,$01,$0C,$0C,$08,$0F,$10,$01,$08,$01,$0A,$01
  .byte $08,$01,$08,$01,$08,$01,$0A,$0B,$03,$03,$04,$04,$06,$07,$04,$04
  .byte $03,$03,$08,$01,$08,$85,$0A,$02,$08,$01,$87,$02,$03,$0B,$03,$03
  .byte $84,$0A,$0E,$03,$03,$08,$01,$08,$01,$08,$01,$08,$01,$08,$01,$08
  .byte $11,$87,$03,$18,$11,$03,$03,$12,$11,$12,$11,$12,$11,$03,$03,$12
  .byte $11,$12,$11,$12,$11,$12,$11,$12,$11,$12,$13,$0A,$85,$13,$01,$0A
  .byte $94,$13,$02,$01,$02,$85,$01,$01,$02,$8D,$01,$05,$03,$03,$04,$03
  .byte $03,$81,$01,$01,$02,$85,$01,$01,$02,$8D,$01,$05,$05,$05,$06,$05
  .byte $05,$81,$01,$01,$02,$85,$01,$01,$02,$8D,$01,$83,$05,$03,$01,$01
  .byte $07,$81,$08,$01,$07,$81,$08,$01,$07,$81,$08,$01,$07,$81,$08,$01
  .byte $07,$81,$08,$01,$07,$81,$08,$01,$07,$81,$08,$01,$07,$83,$08,$01
  .byte $07,$81,$08,$01,$07,$81,$08,$01,$07,$81,$08,$01,$07,$81,$08,$01
  .byte $07,$81,$08,$01,$07,$81,$08,$01,$07,$81,$08,$03,$07,$08,$07,$81
  .byte $08,$01,$07,$81,$08,$01,$07,$81,$08,$01,$07,$81,$08,$01,$07,$81
  .byte $08,$01,$07,$81,$08,$01,$07,$81,$08,$01,$07,$83,$08,$01,$07,$81
  .byte $08,$01,$07,$90,$09,$02,$08,$07,$81,$08,$03,$07,$08,$07,$81,$08
  .byte $01,$07,$81,$08,$01,$07,$81,$08,$01,$07,$81,$08,$01,$07,$81,$08
  .byte $01,$07,$81,$08,$01,$07,$81,$08,$01,$07,$81,$08,$00

PAT3:   ; HOUSE
  .byte $8E,$00,$86,$F0,$86,$0F,$84,$00,$02,$3F,$1F,$85,$00,$01,$FE,$84
  .byte $00,$02,$3F,$3F,$82,$F0,$04,$0F,$3F,$3F,$7F,$82,$00,$16,$80,$E0
  .byte $E0,$F0,$9F,$8F,$CF,$C7,$E3,$F3,$F1,$F9,$FE,$FC,$FC,$F8,$F1,$F3
  .byte $E3,$E7,$7F,$7F,$84,$00,$05,$7F,$7F,$3F,$3F,$0F,$81,$00,$05,$F0
  .byte $F0,$E0,$E0,$80,$81,$00,$85,$F0,$03,$00,$F8,$FC,$8C,$00,$02,$C7
  .byte $CF,$84,$00,$85,$0F,$87,$00,$86,$F0,$86,$0F,$FF,$00,$FF,$00,$FF
  .byte $00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF
  .byte $00,$FF,$00,$FF,$00,$FF,$00,$D0,$00,$86,$F0,$86,$0F,$87,$00,$07
  .byte $01,$01,$03,$03,$07,$0F,$0F,$86,$F0,$86,$0F,$84,$00,$02,$08,$18
  .byte $85,$00,$06,$01,$1F,$1F,$3F,$7F,$7F,$81,$00,$86,$F0,$83,$00,$13
  .byte $01,$01,$03,$1C,$3C,$7C,$7E,$FE,$FE,$00,$00,$03,$03,$07,$07,$0F
  .byte $1F,$1F,$3F,$86,$00,$86,$0F,$08,$07,$07,$0F,$1F,$1F,$3F,$7F,$7F
  .byte $81,$80,$81,$C0,$02,$E0,$E0,$82,$00,$06,$01,$01,$03,$07,$3F,$7F
  .byte $84,$00,$86,$0F,$01,$E0,$81,$F0,$81,$F8,$01,$FC,$86,$00,$86,$F0
  .byte $86,$0F,$85,$00,$01,$80,$88,$00,$02,$F0,$F0,$8C,$00,$02,$03,$03
  .byte $86,$00,$82,$0F,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$82,$F0,$86,$00
  .byte $03,$3E,$7F,$E3,$81,$C1,$05,$E3,$7F,$0F,$1F,$B8,$81,$B0,$05,$B8
  .byte $1F,$83,$C7,$EE,$81,$6C,$05,$EE,$C7,$E0,$F1,$3B,$81,$1B,$05,$3B
  .byte $F1,$F8,$FC,$8E,$81,$06,$04,$8E,$FC,$00,$00,$83,$80,$FF,$00,$FF
  .byte $00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$CE
  .byte $00,$82,$0F,$82,$00,$82,$F0,$82,$00,$04,$3E,$3E,$7F,$E3,$81,$C1
  .byte $05,$E3,$0F,$0F,$1F,$B8,$81,$B0,$05,$B8,$83,$83,$C7,$EE,$81,$6C
  .byte $05,$EF,$E0,$E0,$F1,$3B,$81,$1B,$05,$3B,$F8,$F8,$FC,$8E,$81,$06
  .byte $01,$8E,$81,$00,$83,$80,$05,$7F,$3E,$3E,$7F,$E3,$81,$C1,$05,$1F
  .byte $0F,$0F,$1F,$B8,$81,$B0,$05,$C7,$83,$83,$C7,$EE,$81,$6C,$05,$F1
  .byte $E0,$E0,$F1,$3B,$81,$1B,$05,$FC,$F8,$F8,$FC,$8E,$81,$06,$82,$00
  .byte $82,$80,$82,$00,$82,$0F,$8A,$00,$82,$F0,$03,$E3,$7F,$3E,$83,$00
  .byte $03,$B8,$1F,$0F,$83,$00,$03,$EE,$C7,$83,$83,$00,$03,$3B,$F1,$E0
  .byte $83,$00,$03,$8E,$FC,$F8,$83,$00,$01,$80,$86,$00,$85,$7F,$FF,$00
  .byte $FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00
  .byte $FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$98,$00,$00

COL3:   ; HOUSE
  .byte $86,$00,$85,$AA,$01,$66,$85,$A1,$01,$61,$85,$A1,$01,$61,$84,$AA
  .byte $02,$A1,$61,$85,$AA,$01,$61,$84,$AA,$02,$A1,$61,$82,$A1,$81,$BA
  .byte $01,$B6,$82,$AA,$81,$BA,$01,$B6,$85,$A1,$01,$61,$85,$A1,$03,$61
  .byte $A1,$A1,$83,$AA,$01,$66,$83,$B1,$81,$11,$83,$B1,$81,$11,$85,$A6
  .byte $03,$66,$61,$61,$8C,$66,$02,$61,$61,$84,$66,$85,$A6,$01,$66,$86
  .byte $55,$8E,$51,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF
  .byte $00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$C8
  .byte $00,$85,$AA,$01,$66,$85,$A1,$01,$61,$85,$A1,$01,$61,$87,$55,$85
  .byte $F5,$81,$51,$83,$F1,$86,$51,$84,$55,$02,$F5,$F5,$85,$55,$84,$F5
  .byte $81,$FF,$86,$F1,$83,$55,$87,$F5,$02,$FF,$FF,$86,$F5,$86,$FF,$83
  .byte $51,$81,$F1,$8E,$F5,$82,$55,$84,$F5,$84,$FF,$86,$F1,$86,$F5,$86
  .byte $EE,$8E,$E1,$85,$11,$01,$F1,$85,$66,$05,$11,$66,$66,$61,$61,$81
  .byte $66,$05,$11,$66,$66,$11,$11,$81,$66,$05,$11,$66,$66,$61,$61,$81
  .byte $66,$01,$11,$82,$88,$82,$B8,$FF,$00,$FF,$00,$FF,$00,$FB,$00,$82
  .byte $88,$82,$B8,$86,$88,$85,$A6,$01,$A1,$85,$A6,$01,$A1,$85,$A6,$01
  .byte $A1,$85,$A6,$01,$A1,$85,$A6,$03,$A1,$66,$66,$83,$A6,$01,$11,$FF
  .byte $00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF
  .byte $00,$BD,$00,$85,$66,$01,$11,$86,$EE,$82,$B8,$82,$88,$82,$B8,$82
  .byte $88,$95,$A6,$01,$A1,$8E,$A6,$81,$66,$82,$A6,$01,$A1,$A6,$A6,$82
  .byte $66,$81,$A6,$01,$A1,$82,$66,$81,$E6,$01,$E1,$82,$11,$82,$EE,$82
  .byte $66,$81,$E6,$01,$E1,$81,$A6,$82,$66,$01,$11,$81,$A6,$82,$66,$01
  .byte $11,$81,$A6,$82,$66,$01,$11,$81,$A6,$82,$66,$01,$11,$81,$A6,$82
  .byte $66,$02,$11,$A6,$84,$66,$02,$11,$AA,$85,$EA,$01,$AA,$85,$EE,$FF
  .byte $00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF
  .byte $00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$90,$00,$00

NAM3:   ; HOUSE
  .byte $DE,$00,$83,$01,$02,$02,$03,$83,$01,$01,$02,$88,$01,$05,$04,$01
  .byte $01,$05,$06,$87,$01,$02,$02,$03,$83,$01,$02,$07,$08,$87,$01,$05
  .byte $09,$01,$01,$0A,$0B,$87,$01,$02,$02,$03,$82,$01,$03,$00,$0C,$0D
  .byte $85,$00,$07,$01,$0E,$0F,$10,$10,$11,$12,$87,$01,$02,$02,$03,$82
  .byte $01,$01,$00,$81,$13,$02,$14,$15,$81,$13,$01,$00,$8E,$01,$02,$02
  .byte $03,$82,$01,$01,$00,$81,$13,$02,$14,$15,$81,$13,$01,$00,$8E,$01
  .byte $02,$02,$03,$82,$01,$0A,$00,$04,$04,$05,$06,$07,$04,$08,$04,$00
  .byte $8E,$01,$02,$02,$03,$82,$01,$0A,$00,$04,$09,$0A,$0B,$07,$0C,$0D
  .byte $04,$00,$8E,$01,$02,$02,$03,$82,$01,$0A,$00,$04,$0E,$0F,$0B,$10
  .byte $11,$0F,$12,$00,$8E,$01,$02,$02,$03,$82,$01,$0A,$00,$13,$14,$0F
  .byte $0B,$15,$0F,$0F,$16,$00,$8E,$01,$02,$02,$03,$82,$01,$01,$00,$81
  .byte $17,$02,$18,$19,$81,$17,$01,$1A,$8C,$01,$84,$00,$02,$01,$01,$88
  .byte $00,$89,$01,$81,$1B,$01,$00,$82,$17,$01,$00,$8C,$1B,$01,$1C,$84
  .byte $1D,$01,$1E,$82,$1B,$08,$00,$17,$1F,$60,$17,$00,$1B,$1B,$88,$61
  .byte $81,$1B,$08,$62,$63,$64,$65,$66,$62,$67,$1B,$81,$01,$06,$00,$02
  .byte $03,$04,$02,$00,$8D,$01,$07,$05,$06,$07,$08,$09,$05,$0A,$82,$01
  .byte $01,$00,$82,$02,$01,$00,$8D,$01,$07,$0B,$0C,$0D,$0E,$0F,$0B,$10
  .byte $81,$01,$01,$11,$84,$12,$01,$13,$8C,$01,$09,$14,$15,$16,$17,$18
  .byte $14,$19,$01,$1A,$81,$1B,$01,$1A,$81,$1B,$01,$1A,$81,$1B,$01,$1A
  .byte $81,$1B,$01,$1A,$81,$1B,$01,$1A,$81,$1B,$01,$1A,$81,$1B,$01,$1A
  .byte $83,$1B,$01,$1A,$81,$1B,$01,$1A,$81,$1B,$01,$1A,$81,$1B,$01,$1A
  .byte $81,$1B,$01,$1A,$81,$1B,$01,$1A,$81,$1B,$01,$1A,$81,$1B,$03,$1A
  .byte $1B,$1A,$81,$1B,$01,$1A,$81,$1B,$01,$1A,$81,$1B,$01,$1A,$81,$1B
  .byte $01,$1A,$81,$1B,$01,$1A,$81,$1B,$01,$1A,$81,$1B,$01,$1A,$83,$1B
  .byte $01,$1A,$81,$1B,$01,$1A,$81,$1B,$01,$1A,$81,$1B,$01,$1A,$81,$1B
  .byte $01,$1A,$81,$1B,$01,$1A,$81,$1B,$01,$1A,$81,$1B,$03,$1A,$1B,$1A
  .byte $81,$1B,$01,$1A,$81,$1B,$01,$1A,$81,$1B,$01,$1A,$81,$1B,$01,$1A
  .byte $81,$1B,$01,$1A,$81,$1B,$01,$1A,$81,$1B,$01,$1A,$81,$1B,$00

PAT4:   ; PARK
  .byte $95,$00,$01,$01,$84,$00,$01,$7F,$86,$00,$06,$C0,$03,$07,$0F,$1F
  .byte $1F,$81,$3F,$86,$00,$05,$E0,$F0,$F8,$FC,$FC,$81,$FE,$82,$3F,$04
  .byte $1F,$1F,$0F,$07,$82,$FE,$04,$FC,$FC,$F8,$F0,$82,$00,$04,$55,$AA
  .byte $55,$AA,$82,$00,$1C,$55,$70,$F8,$F8,$03,$01,$00,$00,$55,$AA,$55
  .byte $AA,$00,$00,$7F,$00,$55,$AA,$55,$AA,$E0,$C0,$00,$00,$55,$AA,$55
  .byte $AA,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF
  .byte $00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$8A
  .byte $00,$17,$FE,$01,$FD,$F9,$F1,$00,$00,$80,$BF,$C0,$C0,$CF,$C7,$FD
  .byte $03,$07,$07,$0F,$1F,$3F,$3F,$FC,$FE,$87,$00,$05,$7F,$BF,$C0,$E0
  .byte $E0,$84,$00,$02,$F0,$F0,$84,$00,$02,$FE,$FC,$84,$00,$02,$F3,$F3
  .byte $84,$00,$02,$F8,$F8,$84,$00,$02,$3F,$1F,$84,$00,$02,$F3,$F3,$86
  .byte $00,$84,$0F,$0B,$00,$00,$FE,$FC,$F9,$F3,$E3,$07,$0F,$1F,$7F,$8D
  .byte $00,$05,$F0,$F8,$FC,$FE,$FE,$84,$00,$05,$7F,$3F,$3F,$9F,$CF,$85
  .byte $00,$01,$01,$82,$00,$04,$20,$70,$F8,$FC,$86,$F0,$0A,$FC,$F8,$F0
  .byte $E0,$E0,$C0,$80,$00,$F3,$F3,$81,$13,$81,$F3,$02,$F8,$F8,$81,$FC
  .byte $81,$FE,$08,$1F,$0F,$07,$03,$03,$01,$00,$00,$86,$F3,$0B,$00,$FE
  .byte $FC,$F8,$F0,$E1,$C0,$80,$1F,$3F,$7F,$8B,$00,$06,$C7,$E0,$F0,$F8
  .byte $F8,$FC,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$06,$00,$00,$7F,$3F,$1F
  .byte $0F,$85,$00,$0A,$FE,$03,$07,$0F,$1F,$3F,$3F,$7F,$00,$FE,$87,$00
  .byte $06,$80,$C0,$E0,$E0,$F0,$F8,$86,$F0,$85,$00,$01,$01,$86,$F3,$01
  .byte $FE,$89,$00,$81,$80,$04,$C0,$F3,$F3,$13,$83,$F3,$09,$00,$00,$FE
  .byte $FC,$F8,$F0,$8F,$8F,$80,$91,$00,$08,$DF,$DF,$8F,$8F,$0F,$07,$03
  .byte $01,$87,$00,$03,$7F,$3F,$1F,$82,$00,$04,$DF,$DF,$8F,$8F,$84,$00
  .byte $06,$FE,$FC,$FD,$F3,$07,$0F,$82,$F0,$8A,$00,$82,$0F,$08,$FC,$FE
  .byte $00,$00,$DF,$DF,$8F,$8F,$81,$00,$05,$80,$3F,$1F,$0F,$07,$8A,$00
  .byte $04,$FE,$FE,$FC,$FC,$86,$F0,$81,$01,$01,$03,$82,$00,$86,$F3,$86
  .byte $00,$81,$C0,$05,$E0,$FE,$FE,$FC,$FC,$86,$F3,$08,$00,$00,$7F,$7F
  .byte $3F,$1F,$0F,$0F,$86,$F0,$02,$00,$00,$81,$FE,$04,$F8,$FC,$E0,$8F
  .byte $81,$07,$04,$03,$03,$01,$01,$82,$00,$09,$FE,$FE,$FC,$FC,$0F,$07
  .byte $03,$03,$01,$81,$00,$01,$8F,$81,$07,$09,$03,$03,$01,$01,$F8,$F0
  .byte $E0,$C0,$80,$81,$00,$02,$F0,$F0,$86,$00,$01,$03,$82,$07,$0B,$03
  .byte $0F,$0F,$00,$80,$C0,$E0,$E0,$F0,$03,$01,$87,$00,$05,$7F,$3F,$1F
  .byte $0F,$07,$84,$00,$03,$FE,$FE,$FC,$81,$F8,$81,$F0,$01,$E0,$86,$F0
  .byte $82,$00,$81,$7F,$01,$3F,$86,$F3,$01,$FC,$81,$F8,$81,$F0,$01,$E0
  .byte $82,$F3,$82,$7C,$04,$07,$03,$01,$01,$81,$7F,$01,$3F,$86,$F0,$81
  .byte $00,$09,$FE,$FC,$F8,$F8,$F0,$01,$00,$20,$20,$82,$70,$01,$1C,$81
  .byte $F8,$81,$F0,$01,$E0,$86,$03,$12,$F8,$FC,$FE,$7F,$3F,$1F,$0F,$07
  .byte $01,$00,$20,$20,$F0,$F0,$C0,$E0,$03,$01,$87,$00,$06,$7F,$3F,$1F
  .byte $0F,$07,$FC,$81,$F8,$81,$F0,$0A,$E0,$FC,$F8,$F0,$F0,$E0,$C0,$80
  .byte $80,$E0,$81,$C0,$81,$80,$01,$03,$86,$F0,$01,$3F,$81,$1F,$81,$0F
  .byte $01,$07,$86,$F3,$86,$F0,$03,$E0,$C0,$80,$83,$00,$81,$F8,$82,$FC
  .byte $01,$FE,$86,$03,$04,$07,$03,$C1,$C0,$81,$80,$0A,$03,$F0,$F8,$F8
  .byte $FC,$7E,$80,$C0,$E0,$3F,$81,$1F,$07,$0F,$0F,$8F,$C7,$07,$03,$01
  .byte $83,$00,$01,$E0,$81,$C0,$81,$80,$01,$03,$86,$00,$82,$C0,$82,$00
  .byte $86,$03,$05,$F0,$F8,$FC,$FE,$FE,$81,$00,$08,$1F,$1F,$0F,$07,$03
  .byte $01,$81,$C0,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FA,$00,$86,$F0,$84
  .byte $00,$02,$0F,$0F,$86,$F0,$86,$03,$10,$E0,$E0,$F0,$F8,$FC,$FE,$00
  .byte $00,$7F,$3F,$1F,$0F,$07,$07,$03,$81,$86,$F0,$84,$0F,$19,$00,$00
  .byte $80,$C0,$E0,$F0,$F8,$F8,$FC,$FE,$00,$7F,$7F,$3F,$1F,$0F,$07,$03
  .byte $01,$81,$C0,$E0,$E0,$F0,$F8,$82,$00,$82,$7F,$01,$00,$86,$7F,$8F
  .byte $00,$85,$7F,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF
  .byte $00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$E0
  .byte $00,$00

COL4:   ; PARK
  .byte $86,$00,$8D,$55,$01,$B5,$84,$55,$02,$B5,$BB,$85,$55,$87,$B5,$86
  .byte $BB,$96,$B5,$82,$55,$82,$75,$82,$55,$08,$75,$F7,$F7,$F5,$B5,$B5
  .byte $55,$55,$82,$75,$04,$BB,$BB,$B5,$55,$82,$75,$04,$B5,$B5,$55,$55
  .byte $82,$75,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00
  .byte $FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00
  .byte $01,$00,$89,$77,$02,$74,$F7,$81,$74,$06,$77,$77,$F7,$74,$F7,$F7
  .byte $81,$74,$83,$F7,$82,$F4,$84,$FF,$81,$77,$02,$74,$74,$81,$F7,$84
  .byte $11,$02,$71,$71,$84,$11,$02,$74,$74,$84,$11,$02,$41,$41,$84,$11
  .byte $02,$F4,$F4,$84,$11,$02,$74,$74,$84,$11,$02,$71,$71,$84,$11,$02
  .byte $77,$77,$84,$71,$02,$77,$77,$83,$74,$01,$F7,$81,$F4,$8D,$FF,$83
  .byte $F4,$81,$FF,$81,$77,$83,$74,$85,$77,$01,$F7,$82,$77,$82,$F7,$86
  .byte $71,$85,$74,$03,$44,$41,$41,$81,$F4,$81,$F1,$86,$F4,$84,$74,$02
  .byte $44,$44,$86,$71,$01,$77,$85,$74,$81,$F4,$81,$FF,$02,$44,$44,$84
  .byte $FF,$03,$44,$44,$74,$83,$F4,$02,$44,$44,$FF,$00,$FF,$00,$FF,$00
  .byte $FB,$00,$82,$77,$82,$74,$85,$77,$01,$74,$83,$F7,$04,$F4,$F4,$FF
  .byte $F7,$85,$FF,$02,$77,$77,$84,$F7,$84,$71,$02,$21,$21,$85,$44,$01
  .byte $F4,$86,$F1,$01,$F4,$85,$FF,$82,$44,$82,$F4,$03,$71,$71,$74,$81
  .byte $41,$04,$21,$21,$77,$77,$82,$74,$03,$42,$42,$74,$91,$44,$82,$42
  .byte $82,$74,$82,$44,$83,$77,$81,$74,$82,$77,$82,$72,$84,$77,$82,$74
  .byte $02,$F7,$F4,$82,$41,$82,$FF,$82,$11,$82,$FF,$82,$41,$04,$F4,$F7
  .byte $FF,$FF,$82,$42,$81,$77,$01,$F7,$82,$74,$82,$77,$82,$55,$82,$77
  .byte $82,$52,$86,$21,$82,$F4,$82,$44,$82,$F1,$82,$41,$82,$FF,$82,$44
  .byte $82,$F4,$82,$42,$86,$21,$04,$77,$77,$74,$74,$82,$54,$82,$71,$82
  .byte $51,$08,$77,$77,$74,$74,$52,$54,$52,$54,$86,$42,$82,$44,$82,$42
  .byte $82,$74,$01,$54,$81,$44,$82,$72,$04,$52,$52,$42,$42,$82,$74,$01
  .byte $54,$81,$44,$02,$41,$41,$84,$44,$03,$11,$11,$41,$83,$81,$03,$41
  .byte $41,$44,$82,$84,$03,$82,$74,$74,$84,$44,$81,$77,$01,$74,$82,$54
  .byte $84,$55,$04,$54,$54,$52,$52,$84,$42,$82,$21,$82,$C1,$82,$44,$82
  .byte $42,$86,$41,$86,$42,$82,$21,$82,$C2,$82,$54,$82,$42,$84,$51,$02
  .byte $41,$41,$81,$55,$83,$54,$02,$42,$22,$84,$C2,$01,$54,$85,$42,$02
  .byte $81,$81,$84,$41,$81,$82,$83,$84,$02,$42,$22,$82,$C2,$04,$82,$82
  .byte $54,$54,$84,$44,$81,$55,$83,$54,$86,$52,$86,$54,$85,$42,$01,$C2
  .byte $86,$C1,$86,$42,$86,$C1,$86,$41,$81,$54,$83,$44,$86,$C2,$86,$41
  .byte $02,$84,$82,$83,$42,$01,$C2,$83,$82,$81,$C8,$86,$42,$81,$54,$83
  .byte $44,$82,$52,$81,$42,$01,$C2,$86,$CC,$82,$C8,$82,$CC,$86,$C1,$83
  .byte $C8,$81,$CC,$86,$C8,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$F2,$00,$86
  .byte $CC,$84,$C1,$02,$61,$61,$84,$CC,$02,$C6,$C6,$8E,$C1,$84,$C8,$02
  .byte $CC,$CC,$86,$C8,$84,$61,$02,$C1,$C1,$84,$C6,$02,$CC,$CC,$86,$C8
  .byte $01,$CC,$8C,$C8,$82,$CC,$82,$C8,$01,$CC,$86,$EA,$86,$EE,$01,$AA
  .byte $85,$EE,$01,$AA,$85,$EA,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00
  .byte $FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00
  .byte $FF,$00,$E0,$00,$00

NAM4:   ; PARK
  .byte $DE,$00,$B8,$01,$03,$02,$03,$04,$9B,$01,$03,$05,$06,$07,$9B,$01
  .byte $03,$08,$06,$09,$81,$01,$8E,$0A,$01,$0B,$87,$0A,$03,$0C,$0D,$0E
  .byte $81,$0A,$82,$01,$02,$02,$03,$87,$01,$03,$04,$05,$06,$8E,$01,$09
  .byte $07,$08,$09,$0A,$0B,$0C,$0D,$07,$0E,$81,$01,$05,$0F,$10,$11,$12
  .byte $13,$84,$01,$02,$14,$15,$85,$01,$08,$16,$17,$18,$19,$1A,$1B,$01
  .byte $16,$81,$01,$02,$1C,$1D,$81,$1E,$02,$1F,$60,$82,$01,$04,$61,$62
  .byte $63,$64,$84,$01,$0C,$65,$66,$67,$68,$69,$6A,$01,$16,$01,$01,$6B
  .byte $6C,$81,$6D,$0C,$6E,$6D,$6F,$70,$01,$71,$72,$73,$74,$75,$76,$77
  .byte $81,$01,$0D,$78,$79,$7A,$7B,$7C,$7D,$7E,$7F,$80,$81,$78,$82,$83
  .byte $81,$6D,$5A,$84,$83,$6D,$6D,$85,$79,$86,$87,$88,$89,$8A,$83,$8B
  .byte $8C,$78,$79,$8D,$8E,$8F,$90,$91,$6D,$92,$93,$94,$95,$96,$92,$97
  .byte $90,$6D,$6D,$92,$97,$90,$6D,$6D,$98,$97,$90,$6D,$99,$9A,$9B,$90
  .byte $9C,$9D,$9E,$9F,$A0,$A1,$A2,$91,$6D,$A0,$A3,$A2,$A4,$A5,$A0,$A6
  .byte $A2,$6D,$6D,$A0,$A6,$A2,$6D,$6D,$A0,$A6,$A2,$6D,$A7,$A8,$A9,$AA
  .byte $6D,$AB,$AC,$AD,$AD,$A1,$AD,$AE,$AD,$AD,$AE,$AD,$A1,$8D,$AD,$04
  .byte $AF,$AD,$B0,$B1,$81,$AD,$03,$01,$01,$02,$82,$01,$06,$03,$01,$04
  .byte $01,$01,$03,$82,$01,$01,$03,$82,$01,$08,$03,$01,$01,$05,$01,$03
  .byte $06,$07,$82,$01,$01,$08,$82,$01,$06,$09,$01,$04,$01,$01,$09,$82
  .byte $01,$01,$09,$82,$01,$09,$09,$01,$01,$05,$01,$09,$01,$0A,$0B,$81
  .byte $01,$01,$04,$84,$01,$01,$04,$8D,$01,$01,$05,$82,$01,$03,$0C,$0D
  .byte $0E,$81,$0F,$01,$0E,$81,$0F,$01,$0E,$81,$0F,$01,$0E,$81,$0F,$01
  .byte $0E,$81,$0F,$01,$0E,$81,$0F,$01,$0E,$81,$0F,$01,$0E,$81,$0F,$03
  .byte $10,$10,$11,$81,$10,$01,$11,$81,$10,$01,$11,$81,$10,$01,$11,$81
  .byte $10,$01,$11,$81,$10,$01,$11,$81,$10,$01,$11,$81,$10,$03,$11,$10
  .byte $0E,$81,$0F,$01,$0E,$81,$0F,$01,$0E,$81,$0F,$01,$0E,$81,$0F,$01
  .byte $0E,$81,$0F,$01,$0E,$81,$0F,$01,$0E,$81,$0F,$01,$0E,$81,$0F,$03
  .byte $10,$10,$11,$81,$10,$01,$11,$81,$10,$01,$11,$81,$10,$01,$11,$81
  .byte $10,$01,$11,$81,$10,$01,$11,$81,$10,$01,$11,$81,$10,$03,$11,$10
  .byte $0E,$81,$0F,$01,$0E,$81,$0F,$01,$0E,$81,$0F,$01,$0E,$81,$0F,$01
  .byte $0E,$81,$0F,$01,$0E,$81,$0F,$01,$0E,$81,$0F,$01,$0E,$81,$0F,$00

PAT5:   ; KARATE
  .byte $8E,$00,$86,$FC,$86,$3F,$86,$00,$86,$FC,$86,$00,$86,$03,$86,$C0
  .byte $8A,$00,$82,$0F,$82,$00,$82,$F0,$86,$0F,$86,$F0,$FF,$00,$FF,$00
  .byte $FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00
  .byte $FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$87,$00,$86,$3F,$86,$00
  .byte $86,$03,$86,$C0,$86,$00,$85,$0F,$01,$1F,$85,$F0,$87,$FC,$81,$00
  .byte $02,$01,$01,$81,$03,$15,$3F,$7F,$FC,$F0,$E0,$E0,$C0,$C0,$FE,$00
  .byte $1F,$07,$03,$03,$01,$01,$00,$00,$80,$C0,$C0,$81,$E0,$82,$FC,$8A
  .byte $00,$82,$03,$04,$01,$01,$00,$00,$81,$C0,$05,$E0,$E0,$F0,$FC,$7F
  .byte $81,$01,$05,$03,$03,$07,$1F,$00,$82,$E0,$04,$C0,$C0,$80,$00,$86
  .byte $03,$86,$00,$02,$3F,$1F,$84,$0F,$02,$FE,$FC,$84,$F0,$86,$3C,$84
  .byte $3F,$88,$00,$84,$3C,$8A,$00,$84,$03,$86,$00,$82,$03,$FF,$00,$FF
  .byte $00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF
  .byte $00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$8E,$00,$84,$3F,$86,$00,$86
  .byte $3F,$86,$00,$82,$3F,$04,$00,$00,$3F,$3F,$FF,$00,$FF,$00,$FF,$00
  .byte $FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00
  .byte $FF,$00,$FF,$00,$FF,$00,$FF,$00,$B7,$00,$00

COL5:   ; KARATE
  .byte $86,$00,$86,$66,$86,$61,$86,$F6,$86,$FF,$86,$F1,$82,$11,$82,$88
  .byte $8E,$F1,$8A,$88,$82,$F8,$82,$88,$92,$F8,$FF,$00,$FF,$00,$FF,$00
  .byte $FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00
  .byte $FF,$00,$FF,$00,$FF,$00,$FF,$00,$87,$00,$86,$F6,$86,$FF,$8E,$F1
  .byte $86,$88,$8E,$F8,$86,$F1,$81,$88,$8C,$F8,$01,$FF,$84,$F8,$02,$88
  .byte $88,$84,$F8,$82,$F1,$82,$11,$82,$FF,$82,$11,$84,$F8,$02,$88,$88
  .byte $8D,$F8,$01,$FF,$85,$F8,$01,$88,$86,$61,$86,$66,$8E,$F8,$8C,$F6
  .byte $02,$66,$66,$84,$FF,$02,$66,$66,$84,$F6,$82,$66,$84,$44,$02,$66
  .byte $66,$84,$64,$86,$44,$82,$64,$82,$44,$82,$66,$82,$44,$FF,$00,$FF
  .byte $00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF
  .byte $00,$FF,$00,$FF,$00,$FF,$00,$F9,$00,$86,$44,$02,$66,$66,$84,$E6
  .byte $02,$66,$66,$84,$EE,$86,$E6,$86,$EE,$82,$E6,$04,$66,$66,$E6,$E6
  .byte $82,$EE,$04,$66,$66,$EE,$EE,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF
  .byte $00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF
  .byte $00,$FF,$00,$FF,$00,$AF,$00,$00

NAM5:   ; KARATE
  .byte $DE,$00,$9B,$01,$04,$02,$01,$01,$03,$81,$04,$01,$03,$81,$04,$01
  .byte $03,$81,$04,$01,$03,$81,$04,$01,$03,$81,$04,$01,$03,$81,$04,$01
  .byte $03,$81,$04,$07,$03,$05,$04,$04,$03,$04,$04,$81,$00,$03,$04,$04
  .byte $03,$81,$04,$01,$03,$84,$06,$02,$04,$03,$81,$04,$02,$03,$04,$81
  .byte $00,$0C,$05,$04,$04,$03,$04,$04,$07,$04,$08,$04,$04,$03,$81,$04
  .byte $09,$03,$09,$09,$0A,$0B,$09,$09,$04,$03,$81,$04,$0B,$03,$04,$07
  .byte $04,$08,$05,$04,$04,$03,$04,$04,$81,$00,$03,$04,$04,$03,$81,$04
  .byte $09,$03,$09,$0C,$04,$04,$0D,$09,$04,$03,$81,$04,$02,$03,$04,$81
  .byte $00,$0C,$05,$04,$04,$01,$02,$02,$03,$02,$04,$02,$02,$01,$81,$02
  .byte $09,$01,$05,$05,$06,$07,$05,$05,$02,$01,$81,$02,$0B,$01,$02,$03
  .byte $02,$04,$08,$02,$02,$01,$02,$02,$81,$00,$03,$02,$02,$01,$81,$02
  .byte $09,$01,$05,$09,$0A,$0B,$0C,$05,$02,$01,$81,$02,$02,$01,$02,$81
  .byte $00,$06,$0D,$0E,$02,$01,$02,$02,$81,$00,$03,$02,$02,$01,$81,$02
  .byte $09,$01,$05,$0F,$10,$11,$12,$05,$02,$01,$81,$02,$0B,$01,$02,$00
  .byte $00,$13,$14,$14,$02,$01,$02,$02,$81,$00,$03,$02,$02,$01,$81,$02
  .byte $09,$01,$05,$05,$15,$16,$05,$05,$02,$01,$81,$02,$09,$01,$02,$00
  .byte $00,$13,$14,$14,$02,$01,$81,$02,$01,$01,$81,$02,$01,$01,$81,$02
  .byte $01,$01,$84,$05,$02,$02,$01,$81,$02,$01,$01,$81,$02,$05,$17,$14
  .byte $14,$02,$18,$81,$19,$01,$18,$81,$19,$01,$18,$81,$19,$01,$18,$81
  .byte $19,$01,$18,$81,$19,$01,$18,$81,$19,$01,$18,$81,$19,$04,$1A,$14
  .byte $14,$19,$9A,$1B,$04,$1C,$14,$14,$1B,$9A,$1D,$04,$1E,$1F,$1F,$1D
  .byte $DE,$01,$01,$02,$85,$03,$01,$02,$85,$03,$01,$02,$85,$03,$01,$02
  .byte $85,$03,$01,$04,$85,$05,$01,$04,$85,$05,$01,$04,$85,$05,$01,$04
  .byte $85,$05,$01,$06,$85,$07,$01,$06,$85,$07,$01,$06,$85,$07,$01,$06
  .byte $85,$07,$01,$04,$85,$05,$01,$04,$85,$05,$01,$04,$85,$05,$01,$04
  .byte $85,$05,$01,$04,$85,$05,$01,$04,$85,$05,$01,$04,$85,$05,$01,$04
  .byte $85,$05,$00

PAT6:   ; BASKET
  .byte $9A,$00,$04,$07,$08,$09,$0A,$82,$00,$04,$07,$88,$89,$8A,$83,$00
  .byte $81,$80,$84,$00,$05,$02,$00,$0C,$08,$07,$83,$00,$03,$8C,$88,$07
  .byte $83,$00,$02,$80,$80,$84,$00,$01,$02,$85,$00,$86,$03,$86,$00,$86
  .byte $C0,$04,$00,$00,$1C,$3E,$81,$7F,$05,$3E,$00,$00,$07,$0F,$84,$00
  .byte $02,$01,$83,$82,$00,$86,$03,$04,$00,$00,$8F,$07,$81,$03,$05,$07
  .byte $00,$00,$1C,$3E,$81,$7F,$05,$3E,$00,$00,$07,$0F,$81,$1F,$05,$0F
  .byte $00,$00,$01,$03,$81,$07,$05,$03,$00,$00,$C0,$E0,$81,$F0,$05,$E0
  .byte $00,$00,$70,$F8,$81,$FC,$05,$F8,$00,$00,$E3,$C1,$81,$80,$05,$C1
  .byte $00,$00,$07,$0F,$81,$1F,$05,$0F,$00,$00,$01,$83,$81,$C7,$05,$83
  .byte $00,$00,$C0,$E0,$81,$F1,$05,$E0,$00,$00,$70,$F8,$81,$FC,$05,$F8
  .byte $00,$00,$1C,$3E,$81,$7F,$05,$3E,$00,$00,$F8,$F0,$81,$E0,$05,$F0
  .byte $00,$00,$01,$83,$81,$C7,$01,$83,$FF,$00,$FF,$00,$FF,$00,$FD,$00
  .byte $02,$C0,$E0,$81,$F1,$05,$E0,$00,$00,$70,$F8,$81,$FC,$05,$F8,$00
  .byte $00,$1C,$3E,$81,$7F,$05,$3E,$00,$00,$07,$0F,$81,$1F,$05,$0F,$00
  .byte $00,$FE,$FC,$81,$F8,$05,$FC,$00,$00,$3F,$1F,$81,$0E,$05,$1F,$00
  .byte $00,$70,$F8,$81,$FC,$05,$F8,$00,$00,$07,$0F,$81,$1F,$05,$0F,$00
  .byte $00,$01,$83,$81,$C7,$01,$83,$86,$C0,$04,$00,$00,$8F,$07,$84,$00
  .byte $02,$1C,$3E,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF
  .byte $00,$FF,$00,$FF,$00,$A1,$00,$84,$3E,$88,$00,$86,$03,$84,$F8,$02
  .byte $00,$00,$84,$3E,$02,$00,$00,$84,$0F,$02,$00,$00,$84,$FC,$02,$00
  .byte $00,$84,$1F,$02,$00,$00,$84,$F8,$02,$00,$00,$84,$3E,$02,$00,$00
  .byte $84,$0F,$02,$00,$00,$84,$83,$02,$00,$00,$84,$E0,$02,$00,$00,$84
  .byte $07,$02,$00,$00,$84,$3E,$02,$00,$00,$84,$0F,$02,$00,$00,$84,$03
  .byte $02,$00,$00,$84,$E0,$02,$00,$00,$84,$F8,$02,$00,$00,$84,$C1,$02
  .byte $00,$00,$84,$0F,$02,$00,$00,$84,$83,$02,$00,$00,$84,$E0,$02,$00
  .byte $00,$84,$F8,$02,$00,$00,$84,$F0,$02,$00,$00,$84,$83,$02,$00,$00
  .byte $86,$C0,$81,$00,$01,$01,$81,$03,$01,$01,$86,$00,$86,$0F,$86,$03
  .byte $FF,$00,$FF,$00,$FF,$00,$FD,$00,$02,$FC,$F8,$81,$70,$05,$F8,$00
  .byte $00,$7F,$3E,$81,$1C,$05,$3E,$00,$00,$1F,$0F,$81,$07,$05,$0F,$00
  .byte $00,$38,$7C,$81,$FE,$05,$7C,$00,$00,$F1,$E0,$81,$C0,$05,$E0,$00
  .byte $00,$FC,$F8,$81,$F0,$05,$F8,$00,$00,$7F,$3F,$81,$1F,$05,$3F,$00
  .byte $00,$1F,$0F,$81,$07,$05,$0F,$00,$00,$C7,$83,$81,$01,$05,$83,$00
  .byte $00,$0E,$1F,$81,$3F,$05,$1F,$00,$00,$FC,$F8,$81,$F0,$05,$F8,$00
  .byte $00,$7F,$3F,$81,$1F,$05,$3F,$00,$00,$1F,$0F,$81,$07,$05,$0F,$00
  .byte $00,$C7,$83,$81,$01,$05,$83,$00,$00,$F1,$E0,$81,$C0,$05,$E0,$00
  .byte $00,$03,$07,$81,$0F,$05,$07,$00,$00,$80,$C0,$81,$E0,$05,$C0,$00
  .byte $00,$1F,$0F,$81,$07,$05,$0F,$00,$00,$C7,$83,$81,$01,$05,$83,$00
  .byte $00,$F1,$E0,$81,$C0,$05,$E0,$00,$00,$FC,$F8,$81,$70,$05,$F8,$00
  .byte $00,$7F,$3F,$81,$1F,$05,$3F,$00,$00,$E0,$F0,$81,$F8,$05,$F0,$00
  .byte $00,$C7,$83,$81,$01,$01,$83,$86,$C0,$86,$F0,$84,$FE,$88,$00,$82
  .byte $0F,$82,$00,$86,$03,$84,$07,$02,$00,$00,$84,$C0,$02,$00,$00,$84
  .byte $0F,$02,$00,$00,$84,$83,$02,$00,$00,$84,$E0,$02,$00,$00,$84,$F8
  .byte $02,$00,$00,$84,$3F,$02,$00,$00,$84,$F0,$02,$00,$00,$84,$83,$02
  .byte $00,$00,$84,$E0,$02,$00,$00,$84,$F8,$02,$00,$00,$84,$3E,$02,$00
  .byte $00,$84,$0F,$02,$00,$00,$84,$7C,$02,$00,$00,$84,$E0,$02,$00,$00
  .byte $84,$F8,$02,$00,$00,$84,$3F,$02,$00,$00,$84,$0F,$02,$00,$00,$84
  .byte $83,$02,$00,$00,$84,$1F,$02,$00,$00,$84,$F8,$02,$00,$00,$84,$3F
  .byte $02,$00,$00,$84,$0F,$02,$00,$00,$84,$83,$02,$00,$00,$82,$F0,$84
  .byte $00,$02,$1C,$3E,$81,$7F,$01,$3E,$86,$03,$04,$00,$00,$70,$F8,$81
  .byte $FC,$05,$F8,$00,$00,$1C,$3E,$81,$7F,$05,$3E,$00,$00,$07,$0F,$81
  .byte $1F,$05,$0F,$00,$00,$FE,$FC,$81,$F8,$05,$FC,$00,$00,$3F,$1F,$81
  .byte $0E,$05,$1F,$00,$00,$70,$F8,$81,$FC,$05,$F8,$00,$00,$1C,$3E,$81
  .byte $7F,$05,$3E,$00,$00,$07,$0F,$81,$1F,$05,$0F,$00,$00,$01,$83,$81
  .byte $C7,$05,$83,$00,$00,$C0,$E0,$81,$F0,$05,$E0,$00,$00,$8F,$07,$81
  .byte $03,$05,$07,$00,$00,$1C,$3E,$81,$7F,$05,$3E,$00,$00,$07,$0F,$81
  .byte $1F,$05,$0F,$00,$00,$01,$03,$81,$07,$05,$03,$00,$00,$C0,$E0,$81
  .byte $F0,$05,$E0,$00,$00,$70,$F8,$81,$FC,$05,$F8,$00,$00,$E3,$C1,$81
  .byte $80,$05,$C1,$00,$00,$07,$0F,$81,$1F,$05,$0F,$00,$00,$01,$83,$81
  .byte $C7,$05,$83,$00,$00,$C0,$E0,$81,$F1,$05,$E0,$00,$00,$70,$F8,$81
  .byte $FC,$05,$F8,$00,$00,$F8,$F0,$81,$E0,$05,$F0,$00,$00,$01,$83,$81
  .byte $C7,$01,$83,$86,$C0,$02,$F0,$F0,$84,$0F,$02,$00,$00,$84,$F0,$02
  .byte $00,$00,$82,$03,$02,$00,$00,$84,$E0,$02,$00,$00,$86,$C0,$02,$00
  .byte $00,$82,$F8,$82,$00,$86,$0F,$84,$F0,$86,$0F,$86,$F0,$86,$03,$04
  .byte $00,$00,$F1,$E0,$81,$C0,$05,$E0,$0F,$0F,$8F,$CF,$81,$EF,$01,$CF
  .byte $84,$FE,$02,$00,$00,$86,$03,$84,$E0,$88,$00,$86,$03,$86,$C0,$FF
  .byte $00,$FF,$00,$FF,$00,$EB,$00,$86,$03,$86,$C0,$88,$00,$84,$0F,$02
  .byte $00,$00,$84,$F0,$8A,$00,$0F,$01,$03,$07,$0E,$00,$03,$1F,$7C,$F0
  .byte $C0,$00,$00,$3F,$00,$EF,$83,$0F,$03,$FE,$00,$F3,$83,$F0,$06,$00
  .byte $E0,$FC,$1F,$07,$01,$84,$00,$06,$C0,$E0,$70,$38,$1C,$1C,$83,$38
  .byte $01,$1C,$86,$00,$86,$0F,$86,$F0,$02,$1C,$1C,$83,$0E,$06,$1C,$1C
  .byte $0E,$07,$03,$01,$84,$00,$05,$C0,$F0,$7C,$1F,$03,$84,$0F,$02,$EF
  .byte $00,$84,$F0,$01,$F3,$82,$00,$0A,$01,$07,$1F,$FC,$E0,$1C,$38,$70
  .byte $E0,$C0,$81,$00,$01,$3F,$85,$0F,$01,$FE,$85,$F0,$FF,$00,$FF,$00
  .byte $FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00
  .byte $FF,$00,$FF,$00,$FF,$00,$FF,$00,$98,$00,$00

COL6:   ; BASKET
  .byte $86,$00,$8A,$55,$01,$FF,$85,$11,$82,$81,$82,$11,$82,$81,$83,$11
  .byte $81,$81,$84,$11,$02,$81,$11,$81,$81,$83,$11,$81,$81,$83,$11,$02
  .byte $81,$81,$84,$11,$01,$81,$85,$11,$86,$51,$82,$11,$82,$55,$86,$51
  .byte $02,$44,$44,$84,$84,$04,$44,$44,$F4,$F4,$82,$FF,$04,$44,$44,$D4
  .byte $D4,$82,$FF,$82,$41,$81,$21,$03,$41,$44,$44,$84,$42,$02,$44,$44
  .byte $84,$A4,$02,$44,$44,$84,$84,$02,$44,$44,$84,$F4,$02,$44,$44,$84
  .byte $F4,$02,$44,$44,$84,$D4,$02,$44,$44,$84,$42,$02,$44,$44,$84,$A4
  .byte $02,$44,$44,$84,$84,$02,$44,$44,$84,$84,$02,$44,$44,$84,$F4,$02
  .byte $44,$44,$84,$D4,$02,$44,$44,$84,$42,$02,$44,$44,$84,$A4,$FF,$00
  .byte $FF,$00,$FF,$00,$FB,$00,$02,$44,$44,$84,$A4,$02,$44,$44,$84,$84
  .byte $02,$44,$44,$84,$F4,$02,$44,$44,$84,$D4,$02,$44,$44,$84,$42,$02
  .byte $44,$44,$84,$42,$02,$44,$44,$84,$A4,$02,$44,$44,$84,$F4,$02,$44
  .byte $44,$84,$D4,$02,$41,$41,$84,$D1,$04,$44,$44,$42,$42,$82,$FF,$04
  .byte $44,$44,$A4,$A4,$82,$FF,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00
  .byte $FF,$00,$FF,$00,$FF,$00,$FF,$00,$9D,$00,$84,$D4,$02,$44,$44,$86
  .byte $FF,$86,$41,$84,$84,$02,$44,$44,$84,$F4,$02,$44,$44,$84,$D4,$02
  .byte $44,$44,$84,$42,$02,$44,$44,$84,$42,$02,$44,$44,$84,$A4,$02,$44
  .byte $44,$84,$84,$02,$44,$44,$84,$F4,$02,$44,$44,$84,$D4,$02,$44,$44
  .byte $84,$D4,$02,$44,$44,$84,$42,$02,$44,$44,$84,$A4,$02,$44,$44,$84
  .byte $84,$02,$44,$44,$84,$F4,$02,$44,$44,$84,$F4,$02,$44,$44,$84,$D4
  .byte $02,$44,$44,$84,$42,$02,$44,$44,$84,$A4,$02,$44,$44,$84,$84,$02
  .byte $44,$44,$84,$84,$02,$44,$44,$84,$F4,$02,$44,$44,$84,$42,$02,$44
  .byte $44,$84,$A4,$02,$44,$44,$84,$A1,$02,$41,$41,$81,$EE,$83,$FE,$86
  .byte $88,$86,$F8,$02,$E1,$E1,$84,$21,$FF,$00,$FF,$00,$FF,$00,$FB,$00
  .byte $02,$EE,$EE,$84,$EA,$02,$EE,$EE,$84,$EA,$02,$EE,$EE,$84,$E8,$02
  .byte $EE,$EE,$84,$FE,$02,$EE,$EE,$84,$ED,$02,$EE,$EE,$84,$E2,$02,$EE
  .byte $EE,$84,$E2,$02,$EE,$EE,$84,$EA,$02,$EE,$EE,$84,$E8,$02,$EE,$EE
  .byte $84,$FE,$02,$EE,$EE,$84,$ED,$02,$EE,$EE,$84,$ED,$02,$EE,$EE,$84
  .byte $E2,$02,$EE,$EE,$84,$EA,$02,$EE,$EE,$84,$E8,$02,$EE,$EE,$84,$FE
  .byte $02,$EE,$EE,$84,$FE,$02,$EE,$EE,$84,$ED,$02,$EE,$EE,$84,$E2,$02
  .byte $EE,$EE,$84,$EA,$02,$EE,$EE,$84,$E8,$02,$EE,$EE,$84,$E8,$02,$EE
  .byte $EE,$84,$FE,$02,$EE,$EE,$84,$ED,$86,$E1,$86,$F8,$84,$E2,$02,$EE
  .byte $EE,$82,$88,$82,$FF,$82,$F8,$82,$FF,$84,$81,$02,$E1,$E1,$84,$FE
  .byte $02,$EE,$EE,$84,$FE,$02,$EE,$EE,$84,$ED,$02,$EE,$EE,$84,$E2,$02
  .byte $EE,$EE,$84,$EA,$02,$EE,$EE,$84,$E8,$02,$EE,$EE,$84,$E8,$02,$EE
  .byte $EE,$84,$FE,$02,$EE,$EE,$84,$ED,$02,$EE,$EE,$84,$E2,$02,$EE,$EE
  .byte $84,$EA,$02,$EE,$EE,$84,$EA,$02,$EE,$EE,$84,$E8,$02,$EE,$EE,$84
  .byte $FE,$02,$EE,$EE,$84,$ED,$02,$EE,$EE,$84,$E2,$02,$EE,$EE,$84,$E2
  .byte $02,$EE,$EE,$84,$EA,$02,$EE,$EE,$84,$E8,$02,$EE,$EE,$84,$FE,$02
  .byte $EE,$EE,$84,$ED,$02,$EE,$EE,$84,$ED,$02,$EE,$EE,$84,$E2,$02,$EE
  .byte $EE,$84,$EA,$02,$EE,$EE,$82,$F8,$82,$FF,$02,$44,$44,$84,$D4,$82
  .byte $41,$81,$81,$03,$41,$44,$44,$84,$84,$02,$44,$44,$84,$F4,$02,$44
  .byte $44,$84,$D4,$02,$44,$44,$84,$42,$02,$44,$44,$84,$42,$02,$44,$44
  .byte $84,$A4,$02,$44,$44,$84,$84,$02,$44,$44,$84,$F4,$02,$44,$44,$84
  .byte $D4,$02,$44,$44,$84,$D4,$02,$44,$44,$84,$42,$02,$44,$44,$84,$A4
  .byte $02,$44,$44,$84,$84,$02,$44,$44,$84,$F4,$02,$44,$44,$84,$F4,$02
  .byte $44,$44,$84,$D4,$02,$44,$44,$84,$42,$02,$44,$44,$84,$A4,$02,$44
  .byte $44,$84,$84,$02,$44,$44,$84,$84,$02,$44,$44,$84,$F4,$02,$44,$44
  .byte $84,$42,$02,$44,$44,$84,$A4,$02,$41,$41,$84,$A1,$02,$A8,$A8,$82
  .byte $FA,$04,$F4,$F4,$88,$88,$82,$F8,$04,$F4,$F4,$88,$88,$82,$F4,$02
  .byte $44,$44,$84,$A4,$02,$44,$44,$84,$F1,$04,$41,$41,$88,$88,$82,$D4
  .byte $04,$44,$44,$88,$88,$82,$F2,$04,$F4,$F4,$A8,$A8,$82,$FA,$02,$F4
  .byte $F4,$8E,$FE,$02,$E1,$E1,$84,$81,$02,$EE,$EE,$84,$E2,$86,$FE,$84
  .byte $E8,$02,$EE,$EE,$84,$D1,$02,$E1,$E1,$84,$E8,$04,$EE,$EE,$FF,$FF
  .byte $84,$44,$02,$F1,$F1,$84,$41,$02,$F1,$F1,$84,$41,$FF,$00,$FF,$00
  .byte $FF,$00,$E3,$00,$86,$44,$8E,$41,$02,$FF,$FF,$84,$BB,$02,$FF,$FF
  .byte $84,$FB,$02,$FF,$FF,$84,$FB,$01,$AA,$85,$BB,$01,$AA,$81,$BB,$82
  .byte $FB,$01,$AA,$83,$FB,$04,$BB,$BB,$FA,$FF,$84,$FB,$02,$FA,$FF,$84
  .byte $FB,$01,$AA,$83,$FB,$03,$BB,$BB,$AA,$81,$BB,$82,$FB,$01,$FA,$85
  .byte $FB,$86,$BB,$96,$FB,$01,$FA,$82,$FB,$84,$BB,$8A,$FB,$01,$FF,$85
  .byte $FB,$01,$FF,$81,$BB,$88,$FB,$81,$BB,$01,$FA,$85,$FB,$01,$FA,$85
  .byte $FB,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF
  .byte $00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$98,$00,$00

NAM6:   ; BASKET
  .byte $DE,$00,$8A,$01,$86,$02,$96,$01,$08,$03,$04,$05,$06,$00,$03,$04
  .byte $05,$96,$01,$08,$07,$08,$09,$0A,$00,$07,$08,$09,$8D,$01,$01,$0B
  .byte $86,$01,$86,$0C,$86,$01,$01,$0D,$81,$01,$7F,$0E,$0F,$10,$11,$12
  .byte $13,$14,$15,$16,$17,$18,$19,$1A,$1B,$1C,$1D,$1E,$1F,$60,$61,$62
  .byte $63,$64,$65,$66,$0E,$67,$68,$69,$6A,$6B,$14,$01,$02,$02,$03,$04
  .byte $05,$06,$07,$08,$09,$0A,$0B,$0C,$0D,$0E,$0F,$10,$11,$12,$13,$14
  .byte $15,$16,$17,$18,$01,$19,$1A,$1B,$02,$02,$06,$1C,$1D,$1E,$1F,$60
  .byte $61,$62,$63,$64,$65,$66,$67,$68,$69,$6A,$6B,$6C,$6D,$6E,$6F,$70
  .byte $71,$72,$73,$74,$75,$76,$77,$78,$79,$1D,$62,$7A,$7B,$7C,$7D,$7E
  .byte $7F,$80,$81,$82,$83,$84,$85,$86,$87,$88,$89,$8A,$8B,$8C,$8D,$8E
  .byte $8F,$90,$91,$92,$93,$94,$95,$78,$96,$7B,$7F,$80,$97,$02,$02,$98
  .byte $99,$9A,$9B,$9C,$9D,$9E,$9F,$A0,$A1,$A2,$A3,$A4,$A5,$A6,$A7,$A8
  .byte $A9,$AA,$AB,$AC,$AD,$97,$AE,$AF,$B0,$02,$02,$9B,$B1,$B2,$B3,$03
  .byte $13,$14,$15,$16,$17,$18,$01,$19,$1A,$B4,$04,$05,$06,$07,$08,$09
  .byte $0A,$0B,$0C,$0D,$0E,$0F,$10,$11,$B5,$B6,$B7,$B8,$B9,$BA,$6D,$BB
  .byte $6F,$70,$71,$72,$73,$74,$75,$76,$77,$BC,$60,$61,$62,$63,$64,$65
  .byte $66,$67,$68,$69,$6A,$6B,$6C,$6D,$78,$6F,$BD,$BA,$BE,$8A,$8B,$BF
  .byte $8D,$8E,$8F,$90,$91,$92,$93,$94,$95,$C0,$7E,$7F,$80,$81,$82,$83
  .byte $84,$85,$86,$87,$88,$89,$8A,$8B,$78,$8D,$02,$8E,$8F,$81,$C1,$01
  .byte $C2,$96,$C1,$01,$C3,$81,$C1,$3E,$00,$00,$01,$02,$00,$00,$01,$01
  .byte $00,$00,$01,$01,$00,$00,$01,$01,$00,$00,$01,$01,$00,$00,$01,$01
  .byte $00,$00,$01,$01,$00,$00,$01,$01,$00,$00,$01,$02,$00,$00,$01,$01
  .byte $00,$00,$01,$01,$00,$00,$01,$01,$00,$00,$01,$01,$00,$00,$01,$01
  .byte $00,$00,$01,$01,$00,$00,$83,$01,$01,$02,$96,$01,$01,$03,$81,$01
  .byte $8D,$04,$02,$05,$06,$8D,$04,$8B,$07,$06,$08,$09,$0A,$0B,$0C,$0D
  .byte $98,$07,$06,$0E,$0F,$10,$11,$0F,$12,$98,$07,$06,$13,$14,$15,$16
  .byte $17,$18,$9A,$07,$02,$19,$1A,$8D,$07,$00

PAT7:   ; BAND
  .byte $88,$00,$16,$03,$0F,$1F,$1F,$3F,$3F,$00,$00,$E0,$F8,$FC,$FC,$FE
  .byte $FE,$00,$00,$FC,$F0,$E0,$E0,$C0,$C0,$82,$00,$24,$C3,$C3,$C1,$C1
  .byte $00,$00,$FC,$F0,$E0,$E0,$C0,$C0,$00,$00,$3F,$3F,$C3,$C3,$C1,$C1
  .byte $00,$00,$FC,$F0,$E0,$E0,$C0,$C0,$00,$00,$C0,$C7,$C3,$C3,$CD,$CD
  .byte $81,$3F,$05,$1F,$1F,$0F,$03,$00,$81,$FE,$05,$FC,$FC,$F8,$E0,$00
  .byte $81,$C0,$04,$E0,$E0,$F0,$FC,$81,$00,$04,$CD,$CF,$C3,$C7,$83,$C0
  .byte $05,$E0,$E0,$F0,$FC,$C0,$81,$C1,$05,$C3,$C3,$C7,$3F,$3F,$81,$C0
  .byte $05,$E0,$E0,$F0,$FC,$00,$81,$C0,$0D,$E0,$E0,$F0,$FC,$00,$F1,$F1
  .byte $CD,$CF,$C3,$C7,$C0,$C0,$81,$3F,$11,$1F,$1F,$0F,$03,$C0,$00,$00
  .byte $E0,$F8,$07,$1F,$3F,$1F,$00,$00,$03,$7F,$84,$00,$01,$E0,$85,$00
  .byte $06,$03,$0F,$F0,$FC,$FE,$FC,$81,$FE,$05,$FC,$07,$1F,$3F,$1F,$81
  .byte $3F,$01,$7F,$82,$00,$81,$FE,$83,$00,$81,$3F,$24,$1F,$F0,$FC,$FE
  .byte $FC,$07,$FE,$FE,$FC,$FC,$F8,$E0,$00,$00,$7F,$3C,$1C,$1C,$0C,$03
  .byte $03,$00,$00,$C1,$3C,$3C,$38,$C0,$C0,$F0,$3F,$3F,$1F,$1F,$0F,$03
  .byte $81,$00,$06,$03,$0F,$1F,$1F,$3F,$C3,$FF,$00,$FF,$00,$FF,$00,$FD
  .byte $00,$05,$E0,$F8,$FC,$FC,$7F,$81,$00,$05,$03,$0F,$1F,$1F,$FC,$81
  .byte $00,$26,$E0,$F8,$FC,$FC,$FE,$81,$07,$00,$E0,$F8,$FC,$FC,$FE,$FE
  .byte $00,$7F,$03,$0C,$1C,$1C,$3C,$3C,$00,$00,$C0,$38,$3C,$3C,$C1,$C1
  .byte $F0,$00,$03,$0F,$1F,$1F,$3F,$3F,$81,$03,$05,$0C,$1C,$1C,$3C,$3C
  .byte $81,$C0,$05,$38,$3C,$3C,$C1,$C1,$FF,$00,$FF,$00,$FF,$00,$FF,$00
  .byte $FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$B5,$00,$81,$3F,$05,$1F
  .byte $1F,$0F,$03,$00,$81,$FE,$0C,$FC,$FC,$F8,$E0,$00,$C7,$C3,$3F,$1F
  .byte $1F,$0F,$03,$81,$00,$16,$7F,$03,$03,$07,$E0,$03,$00,$00,$FC,$1F
  .byte $1F,$0F,$03,$00,$C1,$81,$FE,$FC,$FC,$F8,$E0,$00,$81,$3C,$05,$1C
  .byte $1C,$0C,$03,$03,$81,$C1,$19,$3C,$3C,$38,$C0,$C0,$00,$00,$03,$0F
  .byte $1F,$1F,$3F,$3F,$00,$00,$E0,$F8,$FC,$FC,$FE,$FE,$03,$03,$E0,$07
  .byte $85,$03,$05,$0C,$1C,$1C,$3C,$3C,$81,$C0,$05,$38,$3C,$3C,$C1,$C1
  .byte $83,$03,$03,$07,$E0,$03,$81,$3F,$05,$1F,$1F,$0F,$03,$0F,$81,$FE
  .byte $07,$FC,$FC,$F8,$E0,$F8,$00,$00,$84,$3F,$86,$00,$02,$03,$03,$86
  .byte $00,$84,$FC,$0C,$C0,$C1,$C3,$C7,$CF,$CF,$1E,$DC,$7F,$00,$F0,$C0
  .byte $84,$00,$02,$07,$01,$83,$00,$0E,$C0,$E0,$F0,$F8,$F8,$3C,$1C,$00
  .byte $00,$E0,$F8,$FC,$FC,$1F,$81,$00,$18,$03,$0F,$1F,$1F,$FC,$00,$00
  .byte $01,$E0,$07,$0F,$0F,$1F,$1C,$03,$C3,$E3,$F3,$78,$3B,$3F,$1F,$07
  .byte $0F,$83,$1F,$04,$0F,$C0,$E0,$FC,$82,$F0,$01,$E0,$86,$3F,$FF,$00
  .byte $FF,$00,$FF,$00,$FF,$00,$0F,$00,$FE,$FE,$FC,$F8,$E0,$C0,$80,$00
  .byte $00,$03,$07,$0F,$03,$01,$81,$00,$02,$E0,$F0,$82,$00,$04,$7F,$3F
  .byte $3F,$1F,$86,$FC,$08,$DC,$DC,$1E,$CF,$CF,$C7,$C3,$C1,$83,$00,$02
  .byte $C0,$F0,$86,$00,$02,$E0,$10,$81,$00,$03,$07,$1F,$3F,$81,$00,$01
  .byte $1F,$85,$00,$01,$FC,$83,$00,$07,$04,$00,$00,$80,$F0,$FC,$FE,$86
  .byte $00,$01,$83,$83,$00,$0C,$01,$07,$00,$1F,$1F,$3F,$3B,$78,$F3,$E3
  .byte $C3,$07,$82,$03,$0B,$07,$E0,$03,$C0,$3F,$3F,$1F,$1F,$0F,$03,$00
  .byte $84,$FC,$02,$FE,$FE,$83,$0F,$03,$07,$03,$00,$83,$F8,$03,$F0,$E0
  .byte $00,$84,$1F,$12,$3F,$3F,$7F,$0F,$FC,$F0,$E1,$E1,$C3,$C3,$C1,$83
  .byte $07,$07,$0F,$1F,$1F,$3F,$82,$00,$08,$FE,$FC,$F8,$F0,$00,$00,$F0
  .byte $80,$84,$00,$01,$07,$87,$00,$14,$3F,$1F,$0F,$07,$C1,$E0,$F0,$F0
  .byte $F8,$FC,$FC,$FE,$00,$F8,$9F,$87,$C3,$C3,$E1,$E1,$87,$00,$04,$80
  .byte $C0,$E0,$F8,$83,$00,$03,$01,$03,$0F,$81,$00,$01,$7F,$85,$00,$81
  .byte $C7,$01,$07,$82,$0F,$01,$3F,$81,$7F,$82,$00,$02,$E0,$C0,$81,$80
  .byte $85,$00,$06,$78,$44,$44,$78,$03,$01,$84,$00,$01,$FE,$82,$00,$81
  .byte $7F,$81,$F1,$01,$F3,$82,$F8,$84,$00,$02,$F8,$E0,$84,$00,$07,$0F
  .byte $03,$00,$01,$07,$0F,$1F,$81,$3F,$01,$1F,$85,$00,$01,$FC,$83,$00
  .byte $07,$3F,$3F,$00,$C0,$F0,$F8,$FC,$81,$FE,$83,$0F,$03,$07,$C7,$C7
  .byte $83,$00,$81,$7F,$82,$00,$81,$80,$04,$C0,$50,$48,$44,$8A,$00,$01
  .byte $01,$82,$7F,$82,$00,$83,$F8,$10,$F3,$F1,$F1,$00,$00,$E0,$F8,$FC
  .byte $07,$0F,$1F,$00,$00,$07,$78,$80,$8B,$00,$05,$03,$F0,$FC,$03,$01
  .byte $81,$00,$06,$E0,$F8,$FC,$FC,$7E,$C1,$FF,$00,$FF,$00,$FF,$00,$FF
  .byte $00,$FF,$00,$FF,$00,$B0,$00,$81,$3F,$05,$1F,$1F,$0F,$03,$00,$86
  .byte $3F,$81,$00,$02,$FE,$FE,$81,$FC,$09,$C0,$80,$00,$00,$03,$07,$0F
  .byte $0F,$01,$81,$00,$09,$E0,$F0,$F8,$F8,$00,$00,$7F,$3F,$3F,$81,$1F
  .byte $86,$FC,$81,$FE,$0C,$FC,$FC,$F8,$E0,$00,$1F,$CF,$C7,$1E,$1F,$0F
  .byte $03,$83,$00,$04,$1F,$F8,$E0,$00,$82,$3F,$21,$FC,$0F,$03,$C0,$FD
  .byte $F9,$F1,$3C,$FC,$F8,$E0,$00,$C7,$C3,$C3,$1E,$1E,$0F,$03,$00,$3F
  .byte $3F,$1F,$1F,$0F,$07,$07,$03,$E0,$F0,$F8,$FC,$FE,$86,$00,$02,$80
  .byte $F0,$85,$00,$07,$07,$00,$03,$07,$0F,$1F,$3F,$81,$00,$18,$FE,$FE
  .byte $FC,$FC,$F8,$F0,$F0,$E0,$F1,$E1,$E1,$C3,$C3,$87,$9F,$00,$38,$38
  .byte $3C,$3F,$3F,$1F,$1F,$07,$82,$00,$02,$80,$F8,$86,$00,$07,$0F,$0F
  .byte $00,$00,$01,$03,$0F,$81,$00,$81,$E1,$05,$E3,$E3,$38,$60,$00,$83
  .byte $03,$0B,$07,$E0,$03,$00,$00,$03,$0F,$1F,$1F,$3F,$3F,$82,$FC,$04
  .byte $FE,$FE,$00,$00,$81,$0F,$05,$07,$03,$00,$00,$80,$81,$F8,$02,$F0
  .byte $E0,$81,$00,$82,$1F,$03,$3F,$3F,$7F,$FF,$00,$FF,$00,$FF,$00,$FE
  .byte $00,$1E,$E0,$F8,$FC,$FC,$FE,$FE,$C0,$C0,$03,$0F,$E0,$E0,$C0,$C0
  .byte $3F,$1F,$1F,$07,$03,$03,$FE,$FE,$00,$00,$3F,$1F,$07,$00,$7F,$3F
  .byte $84,$00,$01,$1F,$85,$00,$01,$FC,$81,$00,$1E,$FE,$FC,$F0,$80,$00
  .byte $FE,$C0,$FC,$FC,$F0,$E0,$E0,$3F,$3F,$01,$00,$E0,$F8,$FC,$FC,$FE
  .byte $FE,$00,$7F,$07,$0F,$1F,$1F,$3F,$3F,$81,$0F,$11,$F0,$F3,$F3,$F1
  .byte $F1,$FC,$F0,$03,$0F,$1F,$1F,$3F,$3F,$03,$03,$E0,$07,$82,$03,$84
  .byte $3F,$88,$00,$03,$C0,$E0,$F8,$83,$00,$03,$01,$03,$0F,$83,$00,$84
  .byte $FC,$02,$00,$00,$81,$C0,$25,$E0,$E0,$0F,$03,$C0,$CF,$3E,$3F,$1F
  .byte $1F,$0F,$03,$03,$00,$00,$1F,$FC,$FC,$F8,$F0,$F0,$00,$00,$FC,$1F
  .byte $1F,$0F,$03,$00,$F9,$C1,$FE,$FC,$FC,$F8,$E0,$00,$81,$F1,$02,$F3
  .byte $F3,$81,$F0,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF
  .byte $00,$FF,$00,$B6,$00,$00

COL7:   ; BAND
  .byte $86,$00,$02,$F4,$F4,$84,$54,$02,$F4,$F4,$84,$54,$02,$F4,$F4,$84
  .byte $41,$0C,$F4,$F4,$FD,$FD,$41,$41,$D1,$D1,$F4,$F4,$41,$41,$82,$D1
  .byte $14,$F4,$F4,$D1,$D1,$41,$41,$D1,$D1,$F4,$F4,$41,$41,$D1,$D1,$41
  .byte $41,$F4,$F4,$D4,$41,$82,$D1,$85,$54,$01,$F4,$85,$54,$01,$F4,$85
  .byte $41,$03,$F4,$FD,$FD,$82,$D1,$02,$D4,$D4,$85,$41,$01,$D4,$81,$D1
  .byte $81,$41,$02,$D1,$D4,$83,$D1,$03,$41,$41,$F4,$82,$41,$04,$D1,$41
  .byte $41,$F4,$84,$D1,$02,$D4,$D4,$85,$54,$05,$D4,$F4,$F4,$54,$54,$82
  .byte $A5,$04,$F4,$F4,$54,$A4,$82,$FA,$03,$F4,$F4,$54,$83,$FA,$04,$F4
  .byte $F4,$54,$54,$82,$A5,$82,$54,$81,$A5,$01,$A4,$81,$54,$01,$A4,$82
  .byte $FA,$81,$54,$83,$FA,$82,$54,$81,$A5,$02,$A4,$A5,$84,$54,$03,$F4
  .byte $FA,$A4,$82,$54,$05,$E4,$E4,$FA,$FA,$E5,$81,$54,$03,$E4,$E4,$A5
  .byte $84,$54,$81,$F4,$83,$54,$01,$A5,$FF,$00,$FF,$00,$FF,$00,$FB,$00
  .byte $02,$F4,$F4,$82,$54,$04,$A5,$FA,$F4,$F4,$82,$54,$04,$A5,$FA,$F4
  .byte $F4,$83,$54,$03,$A5,$A4,$F4,$84,$54,$03,$FA,$A4,$E4,$83,$54,$03
  .byte $FA,$FA,$E4,$81,$54,$04,$E5,$E5,$A4,$F4,$84,$54,$81,$E4,$83,$54
  .byte $81,$E4,$81,$54,$02,$E5,$E5,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF
  .byte $00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$B5,$00,$85,$54,$01,$F4,$85
  .byte $54,$03,$F4,$A5,$A5,$83,$54,$04,$F4,$FA,$FA,$A5,$81,$E5,$05,$54
  .byte $E4,$FA,$FA,$A5,$82,$54,$03,$F4,$A5,$A5,$83,$54,$01,$F4,$84,$54
  .byte $02,$E4,$E4,$81,$E5,$81,$54,$04,$E4,$E4,$F4,$F4,$84,$54,$02,$F4
  .byte $F4,$84,$54,$03,$E4,$E4,$54,$83,$E5,$81,$E4,$83,$54,$81,$E4,$81
  .byte $54,$86,$E5,$02,$54,$E4,$85,$54,$01,$F4,$85,$54,$03,$F4,$F5,$F5
  .byte $84,$E5,$02,$F5,$F5,$84,$FE,$02,$E5,$E5,$84,$FE,$02,$F5,$F5,$84
  .byte $E5,$81,$E4,$81,$F1,$04,$FE,$F8,$F4,$FF,$84,$F8,$02,$FF,$FF,$84
  .byte $F8,$81,$F4,$81,$F5,$04,$F8,$F8,$F4,$F4,$82,$54,$04,$85,$F8,$F4
  .byte $F4,$82,$54,$05,$85,$F8,$F4,$F4,$54,$82,$F5,$06,$F8,$E4,$E4,$F4
  .byte $F1,$FE,$81,$F8,$02,$F4,$F4,$84,$F5,$02,$F4,$F4,$84,$F5,$86,$E5
  .byte $FF,$00,$FF,$00,$FF,$00,$FB,$00,$83,$FE,$85,$E1,$02,$F1,$F1,$83
  .byte $E1,$81,$F1,$02,$E1,$E1,$82,$FE,$82,$E1,$86,$E5,$03,$F8,$F8,$FE
  .byte $81,$F1,$02,$E4,$E4,$85,$F8,$01,$FF,$8D,$F8,$01,$FF,$81,$F8,$83
  .byte $FF,$81,$F8,$83,$FF,$85,$F8,$01,$FF,$8D,$F8,$01,$FF,$82,$F8,$05
  .byte $FE,$F1,$F4,$E4,$F5,$83,$E5,$03,$54,$E4,$F5,$84,$54,$01,$F4,$8D
  .byte $E1,$01,$F1,$85,$E1,$01,$F1,$86,$E1,$02,$F4,$F4,$82,$41,$02,$81
  .byte $81,$86,$F8,$82,$FF,$82,$F6,$02,$FF,$FF,$84,$F6,$02,$FF,$FF,$84
  .byte $F6,$82,$FF,$82,$F6,$86,$F8,$04,$FF,$F4,$41,$41,$82,$81,$86,$FE
  .byte $01,$F1,$82,$E1,$81,$FE,$02,$F1,$F1,$81,$E1,$81,$FE,$01,$E1,$85
  .byte $FE,$81,$81,$83,$84,$82,$F8,$82,$FF,$96,$F6,$01,$F8,$82,$FF,$81
  .byte $F6,$82,$81,$82,$84,$84,$FE,$02,$E1,$E1,$84,$FE,$02,$E1,$E1,$87
  .byte $F4,$85,$FF,$01,$F4,$83,$FF,$02,$FE,$FE,$86,$F4,$84,$84,$02,$85
  .byte $85,$83,$FF,$81,$F8,$9A,$F6,$82,$FF,$83,$84,$81,$81,$02,$F4,$F4
  .byte $81,$54,$03,$F5,$85,$85,$81,$F4,$83,$F8,$03,$F4,$F4,$FF,$83,$F8
  .byte $05,$F4,$F4,$54,$F5,$85,$81,$F8,$02,$F4,$F4,$83,$54,$01,$F5,$FF
  .byte $00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$B0,$00,$85,$54,$01
  .byte $F4,$86,$E5,$81,$FE,$85,$E1,$02,$F1,$F1,$83,$E1,$81,$F1,$82,$E1
  .byte $02,$FE,$FE,$84,$E1,$86,$E5,$85,$54,$04,$F4,$F4,$F5,$F5,$82,$54
  .byte $01,$F4,$82,$FF,$04,$F5,$54,$54,$F4,$82,$FE,$04,$F5,$54,$54,$E4
  .byte $81,$F5,$82,$54,$01,$F4,$81,$85,$82,$54,$01,$F4,$86,$F8,$83,$F6
  .byte $81,$FF,$85,$F6,$01,$FF,$85,$F6,$01,$FF,$83,$F6,$81,$FF,$86,$F8
  .byte $83,$81,$03,$41,$41,$F4,$81,$F8,$82,$F5,$01,$F4,$84,$F8,$02,$FF
  .byte $FF,$84,$F8,$02,$FE,$FE,$83,$F8,$81,$FF,$83,$F5,$03,$54,$54,$F4
  .byte $84,$E5,$04,$54,$E4,$F4,$F4,$84,$54,$84,$E1,$02,$FE,$FE,$83,$E1
  .byte $02,$F1,$F1,$84,$E1,$81,$F1,$85,$E1,$01,$FE,$FF,$00,$FF,$00,$FF
  .byte $00,$FB,$00,$02,$F4,$F4,$84,$54,$04,$E4,$E4,$54,$54,$82,$E5,$02
  .byte $84,$84,$82,$85,$04,$54,$54,$FF,$FF,$82,$F8,$02,$84,$84,$84,$FF
  .byte $02,$F8,$F8,$84,$FF,$04,$F8,$F8,$FF,$FF,$83,$F8,$03,$84,$F8,$84
  .byte $82,$85,$04,$54,$54,$F4,$F4,$84,$54,$03,$FF,$F4,$F4,$83,$54,$81
  .byte $FE,$01,$E4,$82,$E1,$02,$F4,$F4,$84,$54,$03,$E4,$E4,$54,$89,$E5
  .byte $02,$F5,$F5,$84,$FE,$02,$F5,$F5,$81,$E1,$81,$FE,$02,$F5,$F5,$81
  .byte $E1,$81,$FE,$02,$F5,$F5,$84,$E5,$02,$F5,$F5,$83,$E5,$04,$54,$54
  .byte $E4,$85,$85,$54,$03,$F8,$F8,$85,$83,$54,$03,$F8,$F8,$85,$82,$54
  .byte $03,$F4,$85,$85,$83,$54,$01,$F4,$83,$E1,$81,$E4,$01,$44,$85,$EE
  .byte $01,$F4,$85,$FE,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00
  .byte $FF,$00,$FF,$00,$A6,$00,$00

NAM7:   ; BAND
  .byte $DE,$00,$7F,$01,$02,$01,$02,$01,$02,$01,$02,$01,$02,$01,$02,$03
  .byte $04,$05,$06,$05,$06,$07,$08,$01,$02,$01,$02,$01,$02,$01,$02,$01
  .byte $02,$01,$02,$09,$0A,$09,$0A,$09,$0A,$09,$0A,$09,$0A,$09,$0A,$0B
  .byte $0C,$0D,$0E,$0F,$0E,$10,$11,$12,$0A,$09,$0A,$09,$0A,$09,$0A,$09
  .byte $0A,$09,$0A,$01,$02,$01,$02,$01,$02,$01,$02,$01,$02,$01,$02,$01
  .byte $02,$01,$02,$01,$02,$01,$13,$14,$15,$16,$02,$01,$02,$01,$02,$01
  .byte $02,$01,$02,$09,$0A,$09,$0A,$09,$0A,$09,$0A,$09,$17,$18,$19,$1A
  .byte $0A,$09,$0A,$09,$0A,$09,$1B,$1C,$1D,$1E,$0A,$09,$0A,$09,$0A,$09
  .byte $0A,$09,$7F,$0A,$01,$02,$01,$02,$1F,$60,$61,$62,$01,$63,$64,$65
  .byte $66,$02,$01,$02,$01,$02,$01,$02,$67,$68,$01,$02,$01,$02,$01,$02
  .byte $01,$02,$01,$02,$01,$02,$01,$02,$03,$04,$05,$06,$01,$02,$07,$08
  .byte $01,$02,$01,$02,$01,$02,$01,$02,$07,$08,$01,$02,$01,$02,$01,$02
  .byte $01,$02,$01,$02,$09,$0A,$09,$0A,$09,$0B,$09,$0A,$09,$0A,$0C,$0D
  .byte $09,$0A,$09,$0A,$09,$0A,$09,$0A,$0C,$0D,$09,$0A,$09,$0A,$09,$0A
  .byte $09,$0A,$09,$0A,$01,$02,$01,$02,$01,$0E,$01,$02,$01,$02,$07,$08
  .byte $0F,$10,$01,$02,$01,$02,$0F,$10,$07,$08,$01,$02,$01,$02,$01,$02
  .byte $01,$02,$04,$01,$02,$09,$11,$81,$12,$7F,$13,$14,$0A,$09,$0A,$0C
  .byte $15,$16,$17,$18,$19,$1A,$1B,$16,$17,$1C,$0D,$09,$0A,$09,$0A,$09
  .byte $1D,$1E,$0A,$09,$0A,$01,$1F,$60,$61,$62,$63,$64,$02,$01,$02,$07
  .byte $65,$66,$67,$68,$69,$6A,$6B,$6C,$6D,$6E,$08,$01,$02,$01,$02,$01
  .byte $6F,$70,$02,$01,$02,$09,$1F,$71,$72,$73,$74,$64,$0A,$09,$0A,$0C
  .byte $0D,$75,$76,$77,$78,$79,$7A,$7B,$7C,$0C,$0D,$09,$0A,$09,$0A,$09
  .byte $0B,$09,$0A,$09,$0A,$01,$1F,$7D,$7E,$7F,$80,$64,$02,$01,$02,$01
  .byte $02,$81,$82,$83,$84,$84,$85,$86,$87,$01,$02,$01,$02,$01,$02,$01
  .byte $0E,$01,$02,$01,$02,$09,$1F,$7D,$88,$7C,$89,$7D,$64,$0A,$8A,$8B
  .byte $8C,$8D,$8E,$8F,$90,$91,$91,$92,$93,$94,$09,$95,$96,$97,$98,$99
  .byte $09,$0B,$09,$0A,$09,$0A,$01,$02,$03,$04,$05,$06,$07,$08,$09,$0A
  .byte $0B,$0C,$0D,$0E,$0F,$10,$11,$12,$13,$14,$01,$15,$16,$17,$18,$19
  .byte $01,$1A,$01,$08,$01,$08,$1B,$02,$1C,$1D,$1E,$1F,$07,$60,$1B,$60
  .byte $61,$60,$1B,$62,$63,$64,$65,$66,$67,$60,$1B,$68,$69,$6A,$6B,$60
  .byte $1B,$6C,$1B,$60,$1B,$60,$01,$6D,$6E,$6F,$70,$6E,$71,$08,$01,$08
  .byte $72,$08,$01,$08,$73,$74,$75,$76,$01,$08,$01,$08,$01,$77,$01,$08
  .byte $01,$1A,$01,$08,$01,$08,$9E,$79,$FE,$78,$00

PAT8:   ; VICTORY
  .byte $8E,$00,$86,$80,$86,$00,$08,$80,$C0,$C0,$E0,$F0,$F0,$F8,$F8,$87
  .byte $00,$0A,$01,$01,$03,$07,$07,$0F,$0F,$FC,$FE,$FE,$87,$00,$04,$80
  .byte $80,$C0,$E0,$81,$00,$01,$40,$86,$00,$01,$02,$87,$00,$06,$01,$03
  .byte $1F,$3F,$3F,$7F,$82,$00,$09,$E0,$F0,$F0,$F8,$FC,$FC,$FE,$00,$80
  .byte $86,$00,$01,$04,$89,$00,$01,$01,$86,$00,$01,$08,$86,$00,$1A,$40
  .byte $03,$07,$07,$0F,$1F,$1F,$3F,$7F,$00,$80,$C0,$C0,$E0,$E0,$F0,$F8
  .byte $00,$00,$01,$11,$03,$03,$07,$0F,$7F,$85,$00,$04,$F8,$FC,$FE,$FE
  .byte $88,$00,$02,$80,$C0,$85,$00,$07,$01,$0F,$1F,$3F,$3F,$7F,$7F,$FF
  .byte $00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF
  .byte $00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$AA,$00,$86,$80,$83
  .byte $00,$03,$7F,$3F,$3F,$86,$00,$08,$C0,$E0,$F0,$F0,$F8,$FC,$FC,$FE
  .byte $81,$00,$01,$04,$8E,$00,$01,$20,$81,$00,$08,$01,$03,$07,$07,$0F
  .byte $1F,$1F,$3F,$84,$00,$0B,$FE,$FE,$1F,$1F,$0F,$0F,$07,$07,$03,$01
  .byte $FE,$87,$00,$07,$80,$80,$C0,$E0,$E0,$F0,$08,$86,$00,$01,$40,$89
  .byte $00,$01,$10,$84,$00,$06,$01,$03,$83,$07,$3F,$7F,$84,$00,$09,$FC
  .byte $FC,$F8,$F8,$F0,$F0,$E0,$C0,$01,$88,$00,$0A,$7F,$7F,$3F,$3F,$1F
  .byte $F8,$F8,$FC,$FC,$FE,$88,$00,$08,$80,$0F,$0F,$1F,$1F,$3F,$7F,$7F
  .byte $84,$00,$06,$FE,$FE,$FC,$C0,$80,$80,$83,$00,$28,$0F,$0F,$07,$07
  .byte $03,$07,$01,$01,$C0,$C0,$E0,$F0,$F0,$F8,$F8,$FC,$01,$01,$03,$07
  .byte $07,$0F,$0F,$1F,$F8,$F8,$F0,$F0,$E0,$E0,$C0,$C0,$00,$7F,$7F,$3F
  .byte $3F,$1F,$1F,$0F,$FF,$00,$FF,$00,$FF,$00,$FB,$00,$02,$FE,$FE,$87
  .byte $00,$05,$80,$80,$C0,$E0,$E0,$81,$00,$01,$40,$86,$00,$01,$02,$86
  .byte $00,$06,$01,$03,$03,$3F,$3F,$7F,$86,$00,$06,$FE,$FE,$FC,$FC,$F8
  .byte $80,$85,$00,$11,$0F,$07,$03,$03,$01,$01,$00,$00,$F0,$F0,$F8,$FC
  .byte $FC,$FE,$00,$00,$80,$86,$00,$01,$04,$84,$00,$33,$07,$07,$0F,$1F
  .byte $1F,$3F,$7F,$7F,$F8,$F0,$E0,$E0,$C0,$C0,$80,$80,$7F,$7F,$3F,$1F
  .byte $1F,$0F,$0F,$07,$80,$C0,$C0,$E0,$E0,$F0,$F8,$F8,$00,$01,$01,$03
  .byte $03,$07,$0F,$0F,$00,$00,$FE,$FC,$FC,$F8,$F8,$F0,$00,$00,$02,$83
  .byte $00,$04,$07,$03,$03,$01,$88,$00,$05,$7F,$7F,$FC,$FE,$FE,$88,$00
  .byte $03,$80,$C0,$C0,$84,$00,$07,$01,$01,$1F,$3F,$3F,$7F,$7F,$81,$00
  .byte $06,$F0,$E0,$E0,$C0,$80,$80,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF
  .byte $00,$FF,$00,$FF,$00,$FF,$00,$B8,$00,$86,$80,$86,$00,$08,$3F,$3F
  .byte $1F,$1F,$0F,$07,$07,$03,$86,$00,$1B,$E0,$F0,$F0,$F8,$FC,$FC,$FE
  .byte $FE,$03,$07,$07,$0F,$1F,$1F,$3F,$3F,$FE,$FE,$FC,$FC,$F8,$F0,$F0
  .byte $E0,$03,$01,$01,$88,$00,$0B,$7F,$3F,$3F,$00,$80,$80,$C0,$E0,$E0
  .byte $F0,$F8,$81,$00,$06,$01,$03,$03,$07,$0F,$7F,$8B,$00,$07,$FE,$FE
  .byte $E0,$C0,$C0,$80,$80,$81,$00,$06,$1F,$1F,$0F,$0F,$07,$07,$90,$00
  .byte $04,$F8,$FC,$FC,$FE,$8A,$00,$0E,$0F,$1F,$1F,$3F,$7F,$7F,$00,$00
  .byte $FC,$FC,$F8,$F8,$F0,$F0,$9E,$00,$02,$7F,$7F,$84,$00,$02,$FC,$FC
  .byte $82,$00,$04,$3F,$3F,$BF,$BF,$86,$00,$86,$7F,$86,$BF,$FF,$00,$FF
  .byte $00,$FF,$00,$FB,$00,$02,$FC,$FC,$84,$00,$02,$8F,$8F,$84,$7F,$FF
  .byte $00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF
  .byte $00,$E5,$00,$00

COL8:   ; VICTORY
  .byte $86,$00,$86,$66,$86,$86,$86,$55,$86,$54,$87,$44,$88,$54,$83,$55
  .byte $82,$44,$82,$54,$81,$44,$01,$F4,$86,$44,$01,$F4,$87,$44,$84,$54
  .byte $82,$55,$85,$54,$02,$55,$F4,$86,$44,$01,$F4,$89,$44,$01,$F4,$86
  .byte $44,$01,$F4,$86,$44,$01,$F4,$86,$54,$01,$44,$85,$54,$02,$44,$44
  .byte $85,$54,$85,$55,$82,$54,$82,$55,$84,$44,$02,$54,$54,$85,$44,$85
  .byte $54,$02,$55,$55,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00
  .byte $FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00
  .byte $A0,$00,$86,$66,$86,$86,$83,$55,$81,$54,$86,$55,$86,$54,$81,$44
  .byte $01,$F4,$8E,$44,$01,$F4,$81,$44,$86,$54,$84,$55,$89,$54,$85,$55
  .byte $02,$44,$44,$84,$54,$01,$F4,$86,$44,$01,$F4,$89,$44,$01,$F4,$84
  .byte $44,$84,$54,$84,$55,$87,$54,$85,$44,$81,$55,$88,$54,$81,$55,$85
  .byte $44,$86,$54,$84,$55,$84,$54,$83,$44,$9E,$54,$01,$55,$85,$54,$FF
  .byte $00,$FF,$00,$FF,$00,$FB,$00,$02,$54,$54,$84,$55,$81,$44,$83,$54
  .byte $81,$44,$01,$F4,$86,$44,$01,$F4,$86,$44,$84,$54,$86,$55,$84,$54
  .byte $85,$44,$84,$54,$02,$44,$44,$84,$54,$03,$55,$55,$F4,$86,$44,$01
  .byte $F4,$84,$44,$9E,$54,$01,$44,$85,$54,$02,$55,$55,$84,$54,$03,$44
  .byte $44,$F4,$83,$44,$82,$54,$82,$44,$84,$55,$83,$54,$83,$55,$83,$44
  .byte $81,$54,$84,$44,$85,$54,$81,$55,$84,$54,$02,$44,$44,$FF,$00,$FF
  .byte $00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$AE,$00,$86
  .byte $66,$86,$86,$86,$44,$86,$54,$86,$55,$99,$54,$83,$44,$83,$55,$81
  .byte $54,$01,$44,$85,$54,$81,$44,$84,$54,$8B,$55,$85,$54,$81,$44,$84
  .byte $54,$02,$44,$44,$84,$55,$02,$44,$44,$84,$55,$02,$FF,$FF,$82,$54
  .byte $04,$55,$55,$FF,$FF,$84,$44,$02,$FF,$FF,$84,$54,$02,$FF,$FF,$84
  .byte $54,$04,$44,$44,$FF,$AA,$84,$BB,$02,$FF,$FF,$84,$EE,$8C,$BB,$02
  .byte $BA,$BA,$84,$BB,$02,$B1,$B1,$82,$BB,$82,$B1,$86,$EE,$86,$BA,$86
  .byte $B1,$FF,$00,$FF,$00,$FF,$00,$FB,$00,$02,$B1,$B1,$84,$BB,$02,$B1
  .byte $B1,$84,$BA,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF
  .byte $00,$FF,$00,$FF,$00,$E5,$00,$00

NAM8:   ; VICTORY
  .byte $DE,$00,$06,$01,$02,$02,$03,$03,$04,$92,$05,$10,$06,$03,$03,$01
  .byte $02,$02,$01,$02,$02,$03,$03,$07,$08,$09,$05,$0A,$8D,$05,$0A,$0B
  .byte $0C,$03,$03,$01,$02,$02,$01,$02,$02,$81,$03,$01,$0D,$83,$05,$0E
  .byte $0E,$05,$0F,$05,$10,$05,$05,$11,$05,$05,$12,$05,$05,$13,$81,$03
  .byte $06,$01,$02,$02,$01,$02,$02,$82,$03,$01,$14,$8E,$05,$02,$15,$16
  .byte $81,$03,$06,$01,$02,$02,$01,$02,$02,$82,$03,$02,$17,$18,$8C,$05
  .byte $02,$19,$1A,$82,$03,$07,$01,$02,$02,$01,$02,$02,$03,$82,$04,$05
  .byte $05,$06,$07,$07,$08,$88,$07,$01,$09,$82,$04,$08,$0A,$01,$02,$02
  .byte $01,$02,$02,$0B,$82,$04,$02,$0C,$0D,$82,$07,$0A,$0E,$07,$07,$0F
  .byte $07,$10,$07,$07,$11,$12,$82,$04,$09,$13,$01,$02,$02,$01,$02,$02
  .byte $14,$15,$82,$04,$02,$16,$17,$89,$07,$01,$18,$82,$04,$0A,$19,$1A
  .byte $01,$02,$02,$01,$02,$02,$07,$1B,$83,$04,$01,$1C,$88,$07,$01,$1D
  .byte $83,$04,$0B,$1E,$07,$01,$02,$02,$01,$02,$02,$07,$07,$1F,$82,$04
  .byte $05,$60,$61,$62,$07,$63,$83,$07,$02,$64,$65,$82,$04,$0C,$66,$67
  .byte $07,$01,$02,$02,$01,$02,$02,$07,$07,$68,$83,$04,$01,$69,$83,$07
  .byte $04,$6A,$07,$6B,$6C,$83,$04,$09,$6D,$07,$07,$01,$02,$02,$01,$02
  .byte $02,$81,$07,$01,$6E,$83,$04,$01,$6F,$84,$07,$01,$70,$83,$04,$0A
  .byte $71,$72,$07,$07,$01,$02,$02,$01,$02,$02,$81,$07,$02,$73,$74,$82
  .byte $04,$02,$75,$76,$82,$07,$02,$77,$78,$83,$04,$01,$79,$81,$07,$06
  .byte $01,$02,$02,$01,$02,$02,$82,$03,$01,$04,$83,$05,$01,$06,$82,$03
  .byte $01,$07,$83,$05,$01,$08,$82,$03,$06,$01,$02,$02,$01,$02,$02,$82
  .byte $03,$02,$09,$0A,$83,$05,$05,$0B,$03,$03,$0C,$0D,$82,$05,$02,$0E
  .byte $0F,$82,$03,$06,$01,$02,$02,$01,$02,$02,$83,$03,$02,$10,$11,$82
  .byte $12,$04,$13,$14,$14,$15,$82,$12,$02,$11,$16,$83,$03,$06,$01,$02
  .byte $02,$01,$02,$02,$85,$03,$8A,$17,$85,$03,$03,$01,$02,$02,$88,$18
  .byte $0C,$19,$1A,$19,$1A,$1B,$1C,$19,$1A,$19,$1A,$19,$1A,$88,$18,$88
  .byte $1D,$0C,$19,$1E,$19,$1E,$19,$1F,$19,$1E,$19,$1E,$19,$1E,$92,$1D
  .byte $0C,$19,$1E,$19,$1E,$60,$61,$19,$1E,$19,$1E,$19,$1E,$92,$1D,$0C
  .byte $19,$1E,$19,$1E,$19,$1E,$19,$1E,$19,$1E,$19,$1E,$88,$1D,$00

SC_PATL:
  .byte <PAT0,<PAT1,<PAT2,<PAT3,<PAT4,<PAT5,<PAT6,<PAT7,<PAT8
SC_PATH:
  .byte >PAT0,>PAT1,>PAT2,>PAT3,>PAT4,>PAT5,>PAT6,>PAT7,>PAT8

SC_COLL:
  .byte <COL0,<COL1,<COL2,<COL3,<COL4,<COL5,<COL6,<COL7,<COL8
SC_COLH:
  .byte >COL0,>COL1,>COL2,>COL3,>COL4,>COL5,>COL6,>COL7,>COL8

SC_NAML:
  .byte <NAM0,<NAM1,<NAM2,<NAM3,<NAM4,<NAM5,<NAM6,<NAM7,<NAM8
SC_NAMH:
  .byte >NAM0,>NAM1,>NAM2,>NAM3,>NAM4,>NAM5,>NAM6,>NAM7,>NAM8

JUMP_H:
  .byte $00,$08,$0F,$16,$1B,$20,$26,$2A,$2E,$32,$36,$39,$3A,$3B,$3D,$3E
  .byte $3E,$3E,$3D,$3B,$3A,$39,$36,$32,$2E,$2A,$26,$20,$1B,$16,$0F,$08
  .byte $00

ATK_LEN:
  .byte $00,$0C,$14,$00

ATK_HITAT:
  .byte $00,$08,$0C,$00

ATK_RANGE:
  .byte $00,$20,$26,$00

ATK_DMG:
  .byte $00,$05,$08,$00

ATK_STUN:
  .byte $00,$0B,$0E,$14

ATK_SLIDE:
  .byte $00,$01,$02,$03

SP_TYPE:
  .byte $00,$02,$01,$01,$00

SP_LEN:
  .byte $18,$1A,$1E,$1E,$16

SP_DMG:
  .byte $10,$12,$10,$14,$0C

SP_SPD:
  .byte $03,$00,$04,$03,$05

SP_TOP:
  .byte $06,$07,$02,$06,$06

SP_BOT:
  .byte $00,$02,$03,$01,$00

SP_RANGE:
  .byte $00,$20,$24,$20,$00

SEL_COL:
  .byte $09,$0F,$07,$0D,$03

BOT_COL:
  .byte $04,$02,$08,$0B,$01

PRJ_NAME:
  .byte $70,$70,$70,$70,$78

PRJ_COL:
  .byte $08,$08,$08,$08,$0B

NAMEL:
  .byte $4D,$41,$54,$54,$49,$41,$20,$20,$44,$41,$56,$49,$44,$45,$20,$20
  .byte $54,$48,$4F,$4D,$41,$53,$20,$20,$4E,$49,$43,$48,$4F,$4C,$41,$53
  .byte $45,$4C,$49,$41,$20,$20,$20,$20

NAMER:
  .byte $20,$20,$4D,$41,$54,$54,$49,$41,$20,$20,$44,$41,$56,$49,$44,$45
  .byte $20,$20,$54,$48,$4F,$4D,$41,$53,$4E,$49,$43,$48,$4F,$4C,$41,$53
  .byte $20,$20,$20,$20,$45,$4C,$49,$41

SPECL:
  .byte $46,$49,$52,$45,$20,$42,$41,$4C,$4C,$20,$20,$20,$20,$20,$20,$20
  .byte $44,$52,$41,$47,$4F,$4E,$20,$50,$55,$4E,$43,$48,$20,$20,$20,$20
  .byte $46,$4C,$59,$49,$4E,$47,$20,$4B,$49,$43,$4B,$20,$20,$20,$20,$20
  .byte $42,$55,$4C,$4C,$20,$52,$55,$53,$48,$20,$20,$20,$20,$20,$20,$20
  .byte $54,$48,$55,$4E,$44,$45,$52,$20,$42,$4F,$4C,$54,$20,$20,$20,$20

SPECR:
  .byte $20,$20,$20,$46,$49,$52,$45,$20,$42,$41,$4C,$4C,$20,$20,$20,$20
  .byte $44,$52,$41,$47,$4F,$4E,$20,$50,$55,$4E,$43,$48,$20,$20,$20,$20
  .byte $20,$46,$4C,$59,$49,$4E,$47,$20,$4B,$49,$43,$4B,$20,$20,$20,$20
  .byte $20,$20,$20,$42,$55,$4C,$4C,$20,$52,$55,$53,$48,$20,$20,$20,$20
  .byte $54,$48,$55,$4E,$44,$45,$52,$20,$42,$4F,$4C,$54,$20,$20,$20,$20

STATT:
  .byte $43,$48,$4F,$4F,$53,$45,$20,$20,$52,$45,$41,$44,$59,$21,$20,$20
  .byte $20,$20,$43,$48,$4F,$4F,$53,$45,$20,$20,$52,$45,$41,$44,$59,$21

MSGT:
  .byte $20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20
  .byte $20,$20,$52,$4F,$55,$4E,$44,$20,$31,$20,$20,$20,$20,$20,$20,$20
  .byte $20,$20,$52,$4F,$55,$4E,$44,$20,$32,$20,$20,$20,$20,$20,$20,$20
  .byte $46,$49,$4E,$41,$4C,$20,$52,$4F,$55,$4E,$44,$20,$20,$20,$20,$20
  .byte $20,$20,$20,$46,$49,$47,$48,$54,$21,$20,$20,$20,$20,$20,$20,$20
  .byte $20,$20,$20,$20,$4B,$2E,$4F,$2E,$20,$20,$20,$20,$20,$20,$20,$20
  .byte $20,$20,$54,$49,$4D,$45,$20,$55,$50,$20,$20,$20,$20,$20,$20,$20
  .byte $20,$20,$20,$20,$44,$52,$41,$57,$20,$20,$20,$20,$20,$20,$20,$20

STGN:
  .byte $3C,$20,$20,$20,$4B,$49,$44,$53,$20,$42,$45,$44,$52,$4F,$4F,$4D
  .byte $20,$20,$20,$3E,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20
  .byte $3C,$20,$20,$4D,$4F,$55,$4E,$54,$41,$49,$4E,$20,$48,$4F,$55,$53
  .byte $45,$20,$20,$3E,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20
  .byte $3C,$20,$20,$4D,$4F,$55,$4E,$54,$41,$49,$4E,$20,$50,$41,$52,$4B
  .byte $20,$20,$20,$3E,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20
  .byte $3C,$20,$20,$20,$20,$4B,$41,$52,$41,$54,$45,$20,$47,$59,$4D,$20
  .byte $20,$20,$20,$3E,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20
  .byte $3C,$20,$20,$20,$20,$42,$41,$53,$4B,$45,$54,$20,$47,$59,$4D,$20
  .byte $20,$20,$20,$3E,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20
  .byte $3C,$20,$20,$52,$45,$48,$45,$41,$52,$53,$41,$4C,$20,$52,$4F,$4F
  .byte $4D,$20,$20,$3E,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20

STG_HDR:
  .byte $53,$45,$4C,$45,$43,$54,$20,$53,$54,$41,$47,$45

STG_PRS:
  .byte $50,$52,$45,$53,$53,$20,$41,$20,$42,$55,$54,$54,$4F,$4E

TITLE_REC:
  .byte $0E,$03,$1A,$4A,$4F,$59,$53,$54,$49,$43,$4B,$20,$3D,$20,$4D,$4F
  .byte $56,$45,$20,$20,$55,$50,$20,$3D,$20,$4A,$55,$4D,$50,$0F,$02,$1C
  .byte $42,$54,$4E,$20,$31,$20,$3D,$20,$50,$55,$4E,$43,$48,$20,$20,$20
  .byte $42,$54,$4E,$20,$32,$20,$3D,$20,$4B,$49,$43,$4B,$11,$02,$1B,$42
  .byte $4F,$54,$48,$20,$42,$55,$54,$54,$4F,$4E,$53,$20,$3D,$20,$53,$50
  .byte $45,$43,$49,$41,$4C,$20,$4D,$4F,$56,$45,$12,$01,$1E,$28,$57,$48
  .byte $45,$4E,$20,$54,$48,$45,$20,$53,$50,$45,$43,$49,$41,$4C,$20,$42
  .byte $41,$52,$20,$49,$53,$20,$46,$55,$4C,$4C,$29,$13,$07,$11,$48,$4F
  .byte $4C,$44,$20,$42,$41,$43,$4B,$20,$3D,$20,$42,$4C,$4F,$43,$4B,$16
  .byte $09,$0E,$50,$52,$45,$53,$53,$20,$41,$20,$42,$55,$54,$54,$4F,$4E
  .byte $FF

SEL_REC:
  .byte $04,$06,$13,$43,$48,$4F,$4F,$53,$45,$20,$59,$4F,$55,$52,$20,$57
  .byte $41,$52,$52,$49,$4F,$52,$06,$0C,$08,$4D,$41,$54,$54,$49,$41,$20
  .byte $20,$08,$0C,$08,$44,$41,$56,$49,$44,$45,$20,$20,$0A,$0C,$08,$54
  .byte $48,$4F,$4D,$41,$53,$20,$20,$0C,$0C,$08,$4E,$49,$43,$48,$4F,$4C
  .byte $41,$53,$0E,$0C,$08,$45,$4C,$49,$41,$20,$20,$20,$20,$11,$08,$10
  .byte $55,$50,$2F,$44,$4F,$57,$4E,$20,$3D,$20,$43,$48,$4F,$4F,$53,$45
  .byte $13,$0B,$0A,$42,$54,$4E,$20,$31,$20,$3D,$20,$4F,$4B,$14,$09,$0E
  .byte $42,$54,$4E,$20,$32,$20,$3D,$20,$43,$41,$4E,$43,$45,$4C,$FF

VIC_REC:
  .byte $16,$09,$0E,$50,$52,$45,$53,$53,$20,$41,$20,$42,$55,$54,$54,$4F
  .byte $4E,$FF

VIC_T1:
  .byte $43,$4F,$4E,$47,$52,$41,$54,$55,$4C,$41,$54,$49,$4F,$4E,$53,$21

VIC_T2:
  .byte $54,$48,$45,$20,$57,$49,$4E,$4E,$45,$52,$20,$49,$53
