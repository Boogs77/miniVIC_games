;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;                                                              ;
;   ARCADE_QUANTUM  -  Atari Quantum (1982)                    ;
;   65C02 assembly, TMS9918A Graphics II (bitmap 256x192)      ;
;   Base: asteroids (NMI + trampoline $0FD0, joystick VIA,     ;
;   bitmap shadow in RAM, AY sound engine)                     ;
;                                                              ;
;   - joystick 1 ($D581) = player 1, joystick 2 ($D580) =      ;
;     player 2 (they take turns): the joystick pushes the      ;
;     probe with inertia, like the trackball of the cabinet;   ;
;     a button brakes                                          ;
;   - the probe leaves a trail: close a loop around the        ;
;     particles to destroy them. The loop is found on the      ;
;     grid of the 8x8 cells and its inside is flood-filled     ;
;     from the border of the loop's box                        ;
;   - nucleus 300 (its electrons fly away as positrons),       ;
;     electron 20, positron 200, photon 200, pulsar 400,       ;
;     splitter 100 (splits into 3 triphons), triphon 100,      ;
;     tryd 300. Several particles in one loop multiply the     ;
;     points (x2, x3, x4)                                      ;
;   - electrons and positrons are safe, everything else        ;
;     destroys the probe; pulsars hunt the probe               ;
;   - the wave ends when the nuclei and their positrons are    ;
;     gone; 8 waves with more and more particles, then again   ;
;     faster. 3 probes, extra probe every 10000 points         ;
;   - trail and border are drawn in the bitmap, probe,         ;
;     particles and explosions are sprites (their order turns  ;
;     every frame, so a fifth sprite on a line flickers        ;
;     instead of vanishing)                                    ;
;   - SOUND (2 x AY-3-8910, played from the NMI at 60 Hz):     ;
;     hiss of the moving probe, hum of the pulsars, capture    ;
;     sweep, positron release, splitter, explosions, wave      ;
;     start arpeggio, extra probe beeps                        ;
;   - the main loop writes the VDP only with the interrupt     ;
;     off (VDP_INT_OFF just after the NMI); the NMI only       ;
;     copies the SAT during the vblank and plays the sound     ;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; ---------------- zero page ----------------
PRXL        = $30      ; probe position 8.8 (playfield, Y 0-175)
PRX         = $31
PRYL        = $32
PRY         = $33
PVXL        = $34      ; probe velocity 8.8 signed (VY must follow VX)
PVXH        = $35
PVYL        = $36
PVYH        = $37
PST         = $38      ; probe: 0 alive, 1 exploding, 2 waiting, 3 lost
PSTT        = $39      ; timer of the probe state
INVT        = $3A      ; frames of safety after a new probe
TLH         = $3B      ; trail: newest sample (0-127)
TLL         = $3C      ;        samples alive
LCOL        = $3D      ; cell of the newest sample
LROW        = $3E
IDLE        = $3F      ; frames without moving
LX0         = $40      ; segment: current point
LY0         = $41
LX1         = $42      ;          end point
LY1         = $43
SEGM        = $44      ;          0 draw, 1 erase
CMIN        = $45      ; box of the loop (pixels)
CMAX        = $46
RMIN        = $47
RMAX        = $48
FC          = $4A      ; cell of the new sample
FR          = $4B
LOOPS       = $4C      ; first sample of the loop
NCAP        = $4D      ; particles caught by the loop
NNUC        = $4E      ; nuclei alive
NPOS        = $4F      ; positrons alive
WAVET       = $50      ; frames before the next wave
CYCLE       = $51      ; speed added after every 8 waves (0-3)
PI          = $52      ; particle being handled
RR          = $53      ; first particle in the SAT (turns)
KCLS        = $54      ; speed class
PTYPE       = $55      ; type of a new particle
MSGT        = $56      ; frames of the wave message (play frozen)
CSL         = $57      ; points of the loop (BCD)
CSM         = $58
CSH         = $59
GPTR        = $5A      ; 2 bytes: cell of the trail grid
CAND        = $5E      ; candidate cells checked
TRIES       = $5F      ; attempts to place a particle
CAPACT      = $49      ; 1 = a closed loop is being tested (one particle per frame)
CLP         = $5C      ; snapshot of the loop: first sample
CTH         = $5D      ;                       last sample
CAPI        = $B0      ; next particle to test (counts down)

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
PTR2        = $6E      ; 2 bytes: colour pointer of the cell (shadow)
SPTR        = $70      ; 2 bytes: pattern pointer of the cell (shadow)
TP          = $72      ; 2 bytes: text records
CELLC       = $78      ; cell column (0-31)
CELLR       = $79      ; cell row (0-23)
TCOL        = $7A      ; colour byte (fg<<4 | bg) for texts
PX          = $7B      ; pixel to draw (screen)
PY          = $7C
PCOL        = $7D
P_JOY       = $7E      ; 2 bytes (joystick, 1 = pressed)
TYV         = $80
BIGC        = $81
BIGR        = $82
CLRCOL      = $83      ; colour used by CLEAR_ROWS
NPL         = $84      ; number of players (1-2)
CURP        = $85      ; player in the game (0-1)
LIVES       = $86      ; 2 bytes: probes per player
SCA         = $88      ; 2 bytes: score per player, BCD low
SCB         = $8A      ; 2 bytes: BCD middle
SCC         = $8C      ; 2 bytes: BCD high
HIA         = $8E      ; hi score, BCD low / middle / high
HIB         = $8F
HIC         = $90
WAVE        = $91      ; 2 bytes: wave per player (0 = first)
NXL         = $93      ; 2 bytes: next extra probe (BCD high digits of the score)
JOYC        = $95      ; joystick of the player in the game
PLAYING     = $96      ; 1 = a game is running
EXI         = $97      ; next explosion slot
SPX         = $98      ; SET_SPR: centre, pattern, colour
SPY         = $99
SPN         = $9A
SPC         = $9B
PTS_L       = $9C      ; points to add (BCD)
PTS_M       = $9D
PTS_H       = $9E
PCX         = $9F      ; centre of an explosion
PCY         = $A0
EVPOS       = $A1      ; 1 = positrons released this frame
BLX         = $A2      ; MB_LIM: walls of the bounce
BHX         = $A3
BLY         = $A4
BHY         = $A5

; ---------------- sound: two AY-3-8910, 1 MHz clock ----------------
AY_R_LATCH = $D380       ; right AY
AY_R_WRITE = $D381
AY_L_LATCH = $D384       ; left AY
AY_L_WRITE = $D385

SN1        = $BB         ; sound temporaries (NMI only)
SND_T1     = $BC
SH_L       = $C0         ; shadow of AY left registers 0-10 (11 bytes)
SH_R       = $D0         ; shadow of AY right registers 0-10 (SH_R = SH_L + 16)
SND_UFO    = $DF         ; channel A loop: 1 = pulsar hum
SND_THR    = $E0         ; 1 = hiss of the moving probe
SND_CMD    = $FA         ; command to the sound engine (CMD_*), run by the NMI
SND_MODE   = $FB         ; always 0: effects only
SND_BUSY   = $FC
SND_PH     = $FD
SND_RND    = $FE
SN0        = $FF

WH_ID      = $0700       ; tone effect playing per chip (0 = none)  2 bytes
WH_POS     = $0702       ; frames elapsed
EX_ID      = $0704       ; explosion playing per chip (S_*)
EX_POS     = $0706
SMT0       = $0708       ; temporaries, main loop side
SMT1       = $0709

CMD_GAME   = 1           ; silence + game effects

; ---------------- trail ----------------
TL_X       = $0200       ; 128 samples of the trail (playfield pixels)
TL_Y       = $0280

; ---------------- particles: MAXP slots ----------------
MAXP       = 20
P_T        = $0500       ; type (T_*), 0 = free
P_XL       = $0514       ; centre 8.8 (playfield)
P_XH       = $0528
P_YL       = $053C
P_YH       = $0550
P_VXL      = $0564       ; velocity 8.8 signed (electron: orbit step +1 / -1)
P_VXH      = $0578
P_VYL      = $058C
P_VYH      = $05A0
P_A        = $05B4       ; orbit angle (0-31) / direction
P_PAR      = $05C8       ; nucleus of an electron
P_TM       = $05DC       ; timer
P_CAP      = $05F0       ; 1 = inside the loop
NEXPL      = 4
E_T        = $0610       ; frame of the explosion (0 = free)
E_X        = $0614
E_Y        = $0618

GRID       = $7800       ; 32 x 22 cells: newest trail sample + 1 in the cell

SH_PAT = $4000           ; copy of the screen (pattern) in RAM
SH_COL = $6000           ; copy of the colours

; ---------------- particle types ----------------
T_NUC      = 1           ; nucleus
T_ELE      = 2           ; electron
T_POS      = 3           ; positron
T_PHO      = 4           ; photon
T_PUL      = 5           ; pulsar
T_SPL      = 6           ; splitter
T_TRI      = 7           ; triphon
T_TRY      = 8           ; tryd

; ---------------- parameters ----------------
FIELD_H     = 176        ; playfield: Y 0-175 = screen lines 16-191
PMINX       = 8          ; the probe stays inside these limits
PMAXX       = 247
PMINY       = 8
PMAXY       = 167
QMINX       = 6          ; the particles bounce here
QMAXX       = 249
QMINY       = 6
QMAXY       = 169
ACCEL       = 40         ; push of the joystick (1/256 px per frame^2)
VMAX        = 3          ; speed limit (px per frame)
TLMAX       = 110        ; samples of the trail
MINAGE      = 12         ; samples between the two ends of a loop
CAP_MAX     = 4          ; highest multiplier
TAIL_COL    = $B1        ; trail: light yellow on black
BORD_COL    = $41        ; border: dark blue on black
BTN_MASK    = %00110000
HIDE_Y      = $C0
PROBE_COL   = $0F
CX0         = 128        ; where the probe appears
CY0         = 88
SAFE        = 40         ; new particles stay this far from the probe

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
  JSR CLEAR_VRAM
  JSR INIT_NAME_TABLE
  JSR LOAD_SPRITES
  JSR SND_INIT                 ; AY silent (VDP interrupt still off)
  LDA #$00
  STA DDRA_JOY
  STA DDRB_JOY
  STA VINT                     ; VDP interrupt off (R1 = $C6)
  STA HIA
  STA HIB
  STA HIC
  STA FRAME_CNT
  STA LAST_FRAME
  STA CURP
  STA PLAYING
  STA SND_UFO
  STA SND_THR
  STA EXI
  STA MSGT
  LDX #$01
.rs_p:
  STA SCA,X
  STA SCB,X
  STA SCC,X
  STA LIVES,X
  STA WAVE,X
  DEX
  BPL .rs_p
  LDA #$01
  STA NPL
  LDA #$A5
  STA RND
  JSR HIDE_SPRITES
  JMP TITLE


; ===============================================================
;  TITLE SCREEN (the particles and their points)
; ===============================================================
TITLE:
  LDX #$FF
  TXS                          ; no way back from here: clean stack
  JSR HIDE_SPRITES
  LDA #$00
  STA PLAYING
  STA SND_UFO
  STA SND_THR
  LDA #CMD_GAME
  STA SND_CMD
  JSR VDP_INT_OFF
  JSR CLEAR_ALL
  JSR CLEAR_PARTS
  JSR DRAW_HUD
  LDA #<TITLE_BIG
  STA TP
  LDA #>TITLE_BIG
  STA TP+1
  JSR DRAW_BIGWORDS
  LDA #<TXT_TITLE
  STA TP
  LDA #>TXT_TITLE
  STA TP+1
  JSR DRAW_TEXT
  LDX #$00                     ; one sprite beside every line of the table
  LDY #$00
.t_sp:
  LDA TT_X,X
  STA SPX
  LDA TT_Y,X
  STA SPY
  LDA TT_T,X
  PHX
  TAX
  LDA TY_SPR,X
  STA SPN
  LDA TY_COL,X
  STA SPC
  TYA
  TAX
  JSR SET_SPR
  PLX
  INY
  INY
  INY
  INY
  INX
  CPX #8
  BNE .t_sp
  JSR VDP_INT_ON
.t_rel:                        ; buttons released...
  JSR WAIT_FRAME
  JSR READ_JOY
  LDA P_JOY
  ORA P_JOY+1
  AND #BTN_MASK
  BNE .t_rel
.t_press:                      ; ...then button 1 = 1 player, button 2 = 2 players
  JSR WAIT_FRAME
  JSR READ_JOY
  LDA FRAME_CNT                ; the pulsar of the table pulses
  AND #$08
  LSR A
  CLC
  ADC #24
  STA SAT_BUFFER+(4*4)+2
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
  JMP NEW_GAME


; ===============================================================
;  NEW GAME
; ===============================================================
NEW_GAME:
  LDA #CMD_GAME
  STA SND_CMD
  LDX #$01
.ng_p:
  LDA #$00
  STA SCA,X
  STA SCB,X
  STA SCC,X
  STA WAVE,X
  STA LIVES,X
  LDA #$01
  STA NXL,X
  DEX
  BPL .ng_p
  LDA #$03
  STA LIVES
  LDA NPL
  CMP #$02
  BNE .ng_1
  LDA #$03
  STA LIVES+1
.ng_1:
  LDA #$01
  STA PLAYING
  STZ CURP
  ; fall into WAVE_START


; ===============================================================
;  START OF A WAVE (new wave, or the turn of the other player)
; ===============================================================
WAVE_START:
  LDX #$FF
  TXS
  JSR HIDE_SPRITES
  STZ SND_UFO
  STZ SND_THR
  JSR VDP_INT_OFF
  JSR CLEAR_PLAYFIELD
  JSR DRAW_BORDER
  JSR CLEAR_PARTS
  JSR CLEAR_GRID
  JSR NEW_PROBE
  JSR SPAWN_WAVE
  JSR DRAW_HUD
  LDA NPL                      ; "PLAYER n" with two players
  CMP #$02
  BNE .ws_w
  LDA #<TXT_PLAYER
  STA TP
  LDA #>TXT_PLAYER
  STA TP+1
  JSR DRAW_TEXT
  LDA #$F1
  STA TCOL
  LDA #7
  STA CELLR
  LDA #19
  STA CELLC
  LDA CURP
  CLC
  ADC #$31
  JSR PUT_CHAR
.ws_w:
  LDA #<TXT_WAVE               ; "WAVE nn"
  STA TP
  LDA #>TXT_WAVE
  STA TP+1
  JSR DRAW_TEXT
  LDA #$F1
  STA TCOL
  LDA #9
  STA CELLR
  LDA #17
  STA CELLC
  LDX CURP
  LDA WAVE,X
  INC A
  JSR BIN2BCD
  JSR PUT_BCD
  LDA #100
  STA MSGT
  STZ WAVET
  LDA #W_WAVE
  LDX #2
  JSR SFX_WHISTLE
  JSR VDP_INT_ON


; ===============================================================
;  GAME LOOP: one pass = one frame
; ===============================================================
GAME_LOOP:
  JSR VDP_INT_OFF              ; waits for the vblank and frees the VDP
  JSR READ_JOY
  JSR NEXT_RND
  LDX CURP
  LDA P_JOY,X
  STA JOYC
  LDA MSGT                     ; wave message: everything waits
  BEQ .gl_play
  DEC MSGT
  BNE .gl_draw
  JSR CLEAR_MSG
  BRA .gl_draw
.gl_play:
  JSR UPDATE_PROBE
  JSR UPDATE_PARTS
  JSR CHECK_HITS
  JSR CAPTURE_STEP
  JSR UPDATE_EXPL
  JSR WAVE_CHECK
.gl_draw:
  JSR BUILD_SAT
  JSR VDP_INT_ON
  LDA PST
  CMP #$03
  BEQ PROBE_LOST
  LDA WAVET
  CMP #$01
  BEQ NEXT_WAVE
  JMP GAME_LOOP

NEXT_WAVE:
  LDX CURP
  INC WAVE,X
  JMP WAVE_START


; ---------------------------------------------------------------
; the explosion of the probe is over
; ---------------------------------------------------------------
PROBE_LOST:
  LDX CURP
  DEC LIVES,X
  JSR VDP_INT_OFF
  JSR DRAW_HUD
  JSR VDP_INT_ON
  LDA NPL
  CMP #$02
  BNE .pl_same
  LDA CURP
  EOR #$01
  TAX
  LDA LIVES,X
  BEQ .pl_same
  STX CURP                     ; the other player: his wave starts again
  JSR HIDE_SPRITES
  LDA #40
  JSR WAIT_FRAMES
  JMP WAVE_START
.pl_same:
  LDX CURP
  LDA LIVES,X
  BEQ .pl_over
  LDA #$02                     ; next probe of the same player
  STA PST
  LDA #40
  STA PSTT
  JMP GAME_LOOP
.pl_over:
  JMP GAME_OVER


; ===============================================================
;  GAME OVER
; ===============================================================
GAME_OVER:
  LDX #$FF
  TXS
  LDA #$00
  STA PLAYING
  STA SND_UFO
  STA SND_THR
  JSR HIDE_SPRITES
  LDX #$01                     ; hi score = best of the two players
.go_p:
  LDA SCC,X
  CMP HIC
  BCC .go_n
  BNE .go_new
  LDA SCB,X
  CMP HIB
  BCC .go_n
  BNE .go_new
  LDA SCA,X
  CMP HIA
  BCC .go_n
  BEQ .go_n
.go_new:
  LDA SCA,X
  STA HIA
  LDA SCB,X
  STA HIB
  LDA SCC,X
  STA HIC
.go_n:
  DEX
  BPL .go_p
  JSR VDP_INT_OFF
  JSR CLEAR_PLAYFIELD
  JSR DRAW_BORDER
  JSR DRAW_HUD
  LDA #<OVER_BIG
  STA TP
  LDA #>OVER_BIG
  STA TP+1
  JSR DRAW_BIGWORDS
  LDA #<TXT_PRESS
  STA TP
  LDA #>TXT_PRESS
  STA TP+1
  JSR DRAW_TEXT
  JSR VDP_INT_ON
  LDA #90
  JSR WAIT_FRAMES
  JSR WAIT_FIRE
  JMP TITLE


; ===============================================================
;  PROBE
; ===============================================================
NEW_PROBE:                     ; in the centre, still, no trail
  STZ PRXL
  STZ PRYL
  LDA #CX0
  STA PRX
  LDA #CY0
  STA PRY
  STZ PVXL
  STZ PVXH
  STZ PVYL
  STZ PVYH
  STZ PST
  STZ TLL
  STZ CAPACT
  STZ IDLE
  LDA #$7F
  STA TLH
  LDA #90
  STA INVT
  JMP CLEAR_GRID

UPDATE_PROBE:
  LDA PST
  BEQ .up_alive
  CMP #$01
  BEQ .up_expl
  CMP #$02
  BNE .up_ret
  DEC PSTT                     ; ---- waiting for the next probe
  BNE .up_ret
  JSR NEW_PROBE
  RTS
.up_expl:                      ; ---- exploding: the trail goes away
  LDX #10
.up_er:
  LDA TLL
  BEQ .up_et
  PHX
  JSR ERASE_OLDEST
  PLX
  DEX
  BNE .up_er
.up_et:
  LDA PSTT
  BEQ .up_lost
  DEC PSTT
  RTS
.up_lost:
  LDA TLL
  BNE .up_ret
  LDA #$03
  STA PST
.up_ret:
  RTS
.up_alive:
  LDA INVT
  BEQ .up_joy
  DEC INVT
.up_joy:
  LDA JOYC                     ; ---- push of the joystick
  AND #$04
  BEQ .up_nl
  LDA PVXL
  SEC
  SBC #ACCEL
  STA PVXL
  BCS .up_nl
  DEC PVXH
.up_nl:
  LDA JOYC
  AND #$08
  BEQ .up_nr
  LDA PVXL
  CLC
  ADC #ACCEL
  STA PVXL
  BCC .up_nr
  INC PVXH
.up_nr:
  LDA JOYC
  AND #$01
  BEQ .up_nu
  LDA PVYL
  SEC
  SBC #ACCEL
  STA PVYL
  BCS .up_nu
  DEC PVYH
.up_nu:
  LDA JOYC
  AND #$02
  BEQ .up_nd
  LDA PVYL
  CLC
  ADC #ACCEL
  STA PVYL
  BCC .up_nd
  INC PVYH
.up_nd:
  LDX #$00                     ; ---- friction (stronger with a button), speed limit
  JSR DRAG
  LDX #$02
  JSR DRAG
  LDA PRXL                     ; ---- move
  CLC
  ADC PVXL
  STA PRXL
  LDA PRX
  ADC PVXH
  STA PRX
  LDA PRYL
  CLC
  ADC PVYL
  STA PRYL
  LDA PRY
  ADC PVYH
  STA PRY
  LDA PRX                      ; ---- walls: stop there
  CMP #PMINX
  BCS .up_x1
  LDA #PMINX
  BRA .up_xs
.up_x1:
  CMP #(PMAXX+1)
  BCC .up_y
  LDA #PMAXX
.up_xs:
  STA PRX
  STZ PVXL
  STZ PVXH
.up_y:
  LDA PRY
  CMP #PMINY
  BCC .up_y0
  CMP #(PMAXY+1)
  BCC .up_tr
  LDA #PMAXY
  BRA .up_ys
.up_y0:
  LDA #PMINY
.up_ys:
  STA PRY
  STZ PVYL
  STZ PVYH
.up_tr:                        ; ---- trail
  LDA TLL
  BEQ .up_new
  LDX TLH
  LDA TL_X,X
  CMP PRX
  BNE .up_new
  LDA TL_Y,X
  CMP PRY
  BNE .up_new
  STZ SND_THR                  ; still: the trail shrinks
  INC IDLE
  LDA IDLE
  AND #$03
  BNE .up_ret2
  LDA TLL
  CMP #$02
  BCC .up_ret2
  JMP ERASE_OLDEST
.up_new:
  LDA #$01
  STA SND_THR
  STZ IDLE
  JSR ADD_SAMPLE
  LDA TLL
  CMP #(TLMAX+1)
  BCC .up_ret2
  JMP ERASE_OLDEST
.up_ret2:
  RTS

; X = 0 horizontal, 2 vertical (PVXL/PVXH or PVYL/PVYH): v -= v / 16 (v / 4 braking), |v| <= VMAX
DRAG:
  LDA PVXH,X
  STA T1
  LDA PVXL,X
  STA T0
  LDY #4
  LDA JOYC
  AND #BTN_MASK
  BEQ .dr_sh
  LDY #2
.dr_sh:
  LDA T1                       ; T1:T0 >>= Y (arithmetic)
  CMP #$80
  ROR T1
  ROR T0
  DEY
  BNE .dr_sh
  LDA PVXL,X
  SEC
  SBC T0
  STA PVXL,X
  LDA PVXH,X
  SBC T1
  STA PVXH,X
  BMI .dr_neg
  BNE .dr_pmax
  LDA PVXL,X                   ; very slow: stop
  CMP #$18
  BCS .dr_ret
  STZ PVXL,X
  RTS
.dr_pmax:
  CMP #VMAX
  BCC .dr_ret
  LDA #VMAX
  STA PVXH,X
  STZ PVXL,X
.dr_ret:
  RTS
.dr_neg:
  CMP #$FF
  BNE .dr_nmax
  LDA PVXL,X
  CMP #$E8
  BCC .dr_ret
  STZ PVXL,X
  STZ PVXH,X
  RTS
.dr_nmax:
  CMP #(256-VMAX)
  BCS .dr_ret
  LDA #(256-VMAX)
  STA PVXH,X
  STZ PVXL,X
  RTS


; ===============================================================
;  TRAIL: ring of 128 samples, line pieces in the bitmap,
;  grid of the cells to find the loops
; ===============================================================
; GPTR = GRID + row * 32 (row in A); Y = column
ROW_GRID:
  STA T7
  LSR A
  LSR A
  LSR A
  CLC
  ADC #>GRID
  STA GPTR+1
  LDA T7
  ASL A
  ASL A
  ASL A
  ASL A
  ASL A
  STA GPTR
  RTS

CLEAR_GRID:
  LDA #<GRID
  STA GPTR
  LDA #>GRID
  STA GPTR+1
  LDX #3
  LDA #$00
.cg_p:
  LDY #$00
.cg_b:
  STA (GPTR),Y
  INY
  BNE .cg_b
  INC GPTR+1
  DEX
  BNE .cg_p
  RTS

; new sample at the probe: draws the piece of trail and looks for a loop
ADD_SAMPLE:
  LDA TLL
  BEQ .as_first
  LDX TLH
  LDA TL_X,X                   ; piece from the previous sample
  STA LX0
  LDA TL_Y,X
  STA LY0
  LDA PRX
  STA LX1
  LDA PRY
  STA LY1
  STZ SEGM
  JSR SEG_RUN
  BRA .as_put
.as_first:
  LDA PRX
  STA PX
  LDA PRY
  CLC
  ADC #16
  STA PY
  LDA #TAIL_COL
  STA PCOL
  JSR PLOT_SET
.as_put:
  LDA TLH
  INC A
  AND #$7F
  STA TLH
  TAX
  LDA PRX
  STA TL_X,X
  LDA PRY
  STA TL_Y,X
  INC TLL
  LDA PRX                      ; cell of the new sample
  LSR A
  LSR A
  LSR A
  STA FC
  LDA PRY
  LSR A
  LSR A
  LSR A
  STA FR
  LDA TLL
  CMP #$01
  BEQ .as_mark
  LDA FC
  CMP LCOL
  BNE .as_moved
  LDA FR
  CMP LROW
  BEQ .as_mark                 ; same cell as before
.as_moved:
  LDA FR                       ; the new cell...
  JSR ROW_GRID
  LDY FC
  JSR CHECK_CELL
  BCS .as_loop
  LDA FC                       ; ...and the two corners of a diagonal step
  CMP LCOL
  BEQ .as_mark
  LDA FR
  CMP LROW
  BEQ .as_mark
  LDA FR
  JSR ROW_GRID
  LDY LCOL
  JSR CHECK_CELL
  BCS .as_loop
  LDA LROW
  JSR ROW_GRID
  LDY FC
  JSR CHECK_CELL
  BCS .as_loop
  BRA .as_mark
.as_loop:
  STA LOOPS
  JSR .as_mark
  JMP CAPTURE_LOOP
.as_mark:
  LDA FC
  STA LCOL
  LDA FR
  STA LROW
  JSR ROW_GRID
  LDY FC
  LDA TLH
  INC A
  STA (GPTR),Y
  RTS

; (GPTR),Y = cell: carry set and A = sample if an old sample of the trail is there
CHECK_CELL:
  LDA (GPTR),Y
  BEQ .cc_no
  DEC A
  STA T6
  LDA TLH
  SEC
  SBC T6
  AND #$7F                     ; age of that sample
  CMP #MINAGE
  BCC .cc_no
  CMP TLL
  BCS .cc_no
  LDA T6
  SEC
  RTS
.cc_no:
  CLC
  RTS

; removes the oldest sample (and its piece of trail)
ERASE_OLDEST:
  LDA TLL
  BEQ .eo_ret
  LDA TLH                      ; oldest = head - length + 1
  SEC
  SBC TLL
  INC A
  AND #$7F
  TAX
  STX T5
  LDA TL_X,X
  STA LX0
  LDA TL_Y,X
  STA LY0
  LDA TLL
  CMP #$02
  BCC .eo_one
  TXA
  INC A
  AND #$7F
  TAY
  LDA TL_X,Y
  STA LX1
  LDA TL_Y,Y
  STA LY1
  LDA #$01
  STA SEGM
  JSR SEG_RUN
  BRA .eo_grid
.eo_one:
  JSR CLR_CUR
.eo_grid:
  LDX T5                       ; its cell forgets it
  LDA TL_Y,X
  LSR A
  LSR A
  LSR A
  JSR ROW_GRID
  LDX T5
  LDA TL_X,X
  LSR A
  LSR A
  LSR A
  TAY
  LDA T5
  INC A
  CMP (GPTR),Y
  BNE .eo_dec
  LDA #$00
  STA (GPTR),Y
.eo_dec:
  DEC TLL
.eo_ret:
  RTS

; piece of trail from (LX0,LY0) to (LX1,LY1): SEGM 0 draws it without
; the first point, 1 erases it without the last point
SEG_RUN:
  LDA SEGM
  BEQ .sr_nd
  JSR CLR_CUR
.sr_nd:
  LDA LX0
  CMP LX1
  BNE .sr_st
  LDA LY0
  CMP LY1
  BEQ .sr_ret
.sr_st:
  LDA LX0
  CMP LX1
  BEQ .sr_y
  BCC .sr_xp
  DEC LX0
  BRA .sr_y
.sr_xp:
  INC LX0
.sr_y:
  LDA LY0
  CMP LY1
  BEQ .sr_p
  BCC .sr_yp
  DEC LY0
  BRA .sr_p
.sr_yp:
  INC LY0
.sr_p:
  LDA SEGM
  BNE SEG_RUN
  JSR SET_CUR
  BRA SEG_RUN
.sr_ret:
  RTS

SET_CUR:
  LDA LX0
  STA PX
  LDA LY0
  CLC
  ADC #16
  STA PY
  LDA #TAIL_COL
  STA PCOL
  JMP PLOT_SET

CLR_CUR:
  LDA LX0
  STA PX
  LDA LY0
  CLC
  ADC #16
  STA PY
  JMP PLOT_CLR


; ===============================================================
;  CAPTURE: the samples LOOPS..TLH close a loop (the last one joins
;  the first). A particle is inside when a ray from it to the right
;  crosses the trail an odd number of times.
; ===============================================================
CAPTURE_LOOP:
  LDA CAPACT                   ; a loop is still being tested
  BEQ .cl_new
  RTS
.cl_new:
  STZ NCAP                     ; snapshot of the loop; the box and then the
  STZ CSL                      ; particles are handled one step per frame
  STZ CSM                      ; by CAPTURE_STEP
  STZ CSH
  LDA LOOPS
  STA CLP
  LDA TLH
  STA CTH
  LDA #(MAXP-1)
  STA CAPI
  LDA #$02
  STA CAPACT
  RTS

CAP_BOX:                       ; ---- box of the loop (pixels)
  LDA #$FF
  STA CMIN
  STA RMIN
  STZ CMAX
  STZ RMAX
  LDX CLP
.cl_bb:
  LDA TL_X,X
  CMP CMIN
  BCS .cl_b1
  STA CMIN
.cl_b1:
  CMP CMAX
  BCC .cl_b2
  STA CMAX
.cl_b2:
  LDA TL_Y,X
  CMP RMIN
  BCS .cl_b3
  STA RMIN
.cl_b3:
  CMP RMAX
  BCC .cl_b4
  STA RMAX
.cl_b4:
  CPX CTH
  BEQ .cl_bd
  INX
  TXA
  AND #$7F
  TAX
  BRA .cl_bb
.cl_bd:
  LDA CMAX                     ; too small to hold anything
  SEC
  SBC CMIN
  CMP #12
  BCC .cl_ret
  LDA RMAX
  SEC
  SBC RMIN
  CMP #12
  BCS .cl_go
.cl_ret:
  STZ CAPACT
  RTS
.cl_go:
  LDA #$01
  STA CAPACT
  RTS

CAPTURE_STEP:                  ; tests the next particle inside the box
  LDA CAPACT
  BEQ .cs_ret
  CMP #$02
  BNE .cs_n2
  JMP CAP_BOX                  ; first frame: box of the loop
.cs_n2:
  CMP #$03
  BEQ .cs_fin                  ; last frame: points and explosions
.cs_run:
  LDX CAPI
.cs_tp:
  STZ P_CAP,X
  LDA P_T,X
  BEQ .cs_skip
  LDA P_XH,X                   ; inside the box?
  CMP CMIN
  BCC .cs_skip
  CMP CMAX
  BCS .cs_skip
  STA T4
  LDA P_YH,X
  CMP RMIN
  BCC .cs_skip
  CMP RMAX
  BCS .cs_skip
  STA T5
  JSR INSIDE
  BCC .cs_one
  LDA #$01                     ; caught
  STA P_CAP,X
  INC NCAP
  LDY P_T,X                    ; its points
  SED
  CLC
  LDA CSL
  ADC TY_PL,Y
  STA CSL
  LDA CSM
  ADC TY_PM,Y
  STA CSM
  LDA CSH
  ADC #$00
  STA CSH
  CLD
.cs_one:                       ; one test per frame
  DEX
  STX CAPI
  BPL .cs_ret
  LDA #$03                     ; all tested: the next frame ends it
  STA CAPACT
.cs_ret:
  RTS
.cs_skip:
  DEX
  BPL .cs_tp
.cs_fin:
  STZ CAPACT
  LDA NCAP
  BNE CAP_HIT
  RTS
CAP_HIT:
  STZ PTS_L                    ; points x number caught (up to 4)
  STZ PTS_M
  STZ PTS_H
  LDA NCAP
  CMP #(CAP_MAX+1)
  BCC .cl_m
  LDA #CAP_MAX
.cl_m:
  TAY
.cl_ml:
  SED
  CLC
  LDA PTS_L
  ADC CSL
  STA PTS_L
  LDA PTS_M
  ADC CSM
  STA PTS_M
  LDA PTS_H
  ADC CSH
  STA PTS_H
  CLD
  DEY
  BNE .cl_ml
  JSR ADD_SCORE
  LDA #W_CAPT
  LDX #2
  JSR SFX_WHISTLE
  LDA #S_SMALL
  LDX #2
  JSR SFX_BOOM
  LDX #(MAXP-1)                ; ---- the particles caught explode
.cl_kl:
  LDA P_CAP,X
  BEQ .cl_kn
  STX PI
  JSR KILL_PART
  LDX PI
.cl_kn:
  DEX
  BPL .cl_kl
  RTS

; is (T4, T5) inside the loop LOOPS..TLH? carry set = yes (keeps X)
INSIDE:
  STZ T3                       ; crossings (bit 0)
  LDY CLP
  LDA TL_Y,Y
  CMP T5
  ROL T2                       ; bit 0 = this sample is below the ray
.in_l:
  CPY CTH                      ; next sample (the last one joins the first)
  BEQ .in_last
  INY
  TYA
  AND #$7F
  TAY
  BRA .in_nx
.in_last:
  LDY CLP
.in_nx:
  LDA TL_Y,Y
  CMP T5
  LDA T2
  ROL A                        ; bit 1 = previous, bit 0 = this one
  STA T2
  AND #$03
  BEQ .in_nc                   ; both above
  CMP #$03
  BEQ .in_nc                   ; both below
  LDA TL_X,Y                   ; the piece crosses the line of the ray: on the right?
  CMP T4
  BCC .in_nc
  INC T3
.in_nc:
  CPY CLP
  BNE .in_l
  LDA T3
  LSR A                        ; carry = odd
  RTS


; ===============================================================
;  PARTICLES
; ===============================================================
CLEAR_PARTS:                   ; no particles, no explosions
  STZ CAPACT
  LDX #(MAXP-1)
.cp_l:
  STZ P_T,X
  STZ P_CAP,X
  DEX
  BPL .cp_l
  LDX #(NEXPL-1)
.cp_e:
  STZ E_T,X
  DEX
  BPL .cp_e
  STZ NNUC
  STZ NPOS
  STZ RR
  RTS

; the particles of the wave (WAVE of the player in the game)
SPAWN_WAVE:
  LDX CURP
  LDA WAVE,X
  LSR A
  LSR A
  LSR A
  CMP #4
  BCC .sw_c
  LDA #3
.sw_c:
  STA CYCLE
  LDA WAVE,X
  AND #$07
  STA T3                       ; T3 = wave in the table
  TAX
  LDA WV_NUC,X
  STA T2
.sw_nuc:                       ; nuclei and their electrons
  LDA #T_NUC
  STA PTYPE
  JSR SPAWN
  BCS .sw_more
  STX T4                       ; T4 = slot of the nucleus
  LDX T3
  LDA WV_EPN,X
  STA T5                       ; electrons
  TAY
  LDA EANG_BASE,Y
  STA T6                       ; first angle in EANG
  LDA RND
  AND #$1F
  STA T7                       ; random turn of the whole atom
.sw_el:
  LDA #T_ELE
  STA PTYPE
  JSR SPAWN
  BCS .sw_nn
  LDA T4
  STA P_PAR,X
  LDY T6
  LDA EANG,Y
  CLC
  ADC T7
  AND #$1F
  STA P_A,X
  LDA #$01                     ; nuclei with an odd slot turn the other way
  LDY T4
  CPY #$00
  BEQ .sw_dir
  PHA
  TYA
  LSR A
  PLA
  BCC .sw_dir
  LDA #$FF
.sw_dir:
  STA P_VXL,X
  JSR PLACE_ELEC
  INC T6
  DEC T5
  BNE .sw_el
.sw_nn:
  DEC T2
  BNE .sw_nuc
.sw_more:                      ; the dangerous particles
  LDX T3
  LDA WV_PHO,X
  LDY #T_PHO
  JSR SPAWN_N
  LDX T3
  LDA WV_PUL,X
  LDY #T_PUL
  JSR SPAWN_N
  LDX T3
  LDA WV_SPL,X
  LDY #T_SPL
  JSR SPAWN_N
  LDX T3
  LDA WV_TRY,X
  LDY #T_TRY
  JSR SPAWN_N
  LDX T3
  LDA WV_TRI,X
  LDY #T_TRI
  ; fall into SPAWN_N

SPAWN_N:                       ; A particles of type Y
  STY PTYPE
  STA T5
.sn_l:
  LDA T5
  BEQ .sn_ret
  JSR SPAWN
  DEC T5
  BRA .sn_l
.sn_ret:
  RTS

; a new particle of type PTYPE at a random place away from the probe:
; X = slot (carry clear), carry set if there is no room
SPAWN:
  LDX #$00
.sp_f:
  LDA P_T,X
  BEQ .sp_got
  INX
  CPX #MAXP
  BNE .sp_f
  SEC
  RTS
.sp_got:
  LDA PTYPE
  STA P_T,X
  STZ P_XL,X
  STZ P_YL,X
  STZ P_CAP,X
  STZ P_A,X
  LDA #$FF
  STA P_PAR,X
  LDA RND                      ; splitters split after 3-4 seconds
  ORA #$C0
  STA P_TM,X
  LDA #20
  STA TRIES
.sp_pos:
  JSR NEXT_RND                 ; X 16-239
  CMP #224
  BCC .sp_x
  SBC #224
.sp_x:
  CLC
  ADC #16
  STA P_XH,X
  JSR NEXT_RND                 ; Y 16-159
  AND #$7F
  STA T0
  JSR NEXT_RND
  AND #$0F
  CLC
  ADC T0
  ADC #16
  STA P_YH,X
  DEC TRIES
  BEQ .sp_ok
  LDA P_XH,X                   ; not too close to the probe
  SEC
  SBC PRX
  JSR ABS_A
  CMP #SAFE
  BCS .sp_ok
  LDA P_YH,X
  SEC
  SBC PRY
  JSR ABS_A
  CMP #SAFE
  BCC .sp_pos
.sp_ok:
  LDY PTYPE                    ; direction by type
  JSR NEXT_RND
  AND #$0F
  CPY #T_PHO
  BEQ .sp_diag
  CPY #T_TRI
  BEQ .sp_diag
  CPY #T_TRY
  BNE .sp_vel
  AND #$08                     ; tryd: straight up or down
  BRA .sp_vel
.sp_diag:
  AND #$0C                     ; photon, triphon: diagonal
  ORA #$02
.sp_vel:
  STA P_A,X
  JSR SET_VEL
  CLC
  RTS

; velocity of particle X from its direction P_A and its type
SET_VEL:
  LDY P_T,X
  LDA TY_CLS,Y
  CLC
  ADC CYCLE
  CMP #6
  BCC .sv_c
  LDA #5
.sv_c:
  ASL A
  ASL A
  ASL A
  ASL A
  ORA P_A,X
  TAY
  LDA VEL_XL,Y
  STA P_VXL,X
  LDA VEL_XH,Y
  STA P_VXH,X
  LDA VEL_YL,Y
  STA P_VYL,X
  LDA VEL_YH,Y
  STA P_VYH,X
  RTS

ABS_A:                         ; A = |A| (signed)
  BPL .ab_r
  EOR #$FF
  INC A
.ab_r:
  RTS

; electron X: on its orbit around the nucleus P_PAR
PLACE_ELEC:
  LDY P_PAR,X
  LDA P_A,X
  PHX
  TAX
  LDA ORBX,X
  STA T0
  LDA ORBY,X
  STA T1
  PLX
  LDA P_XH,Y
  CLC
  ADC T0
  STA P_XH,X
  LDA P_YH,Y
  CLC
  ADC T1
  STA P_YH,X
  RTS

UPDATE_PARTS:
  STZ NNUC
  STZ NPOS
  STZ SND_UFO
  LDX #(MAXP-1)
.pa_l:
  STX PI
  LDA P_T,X
  BEQ .pa_n
  ASL A
  TAY
  LDA PART_JMP-2,Y
  STA PTR
  LDA PART_JMP-1,Y
  STA PTR+1
  JSR .pa_jmp
  LDX PI
.pa_n:
  DEX
  BPL .pa_l
  RTS
.pa_jmp:
  JMP (PTR)

PART_JMP:
  .word MOVE_NUC, MOVE_ELE, MOVE_POS, MOVE_BOUNCE
  .word MOVE_PUL, MOVE_SPL, MOVE_BOUNCE, MOVE_BOUNCE

MOVE_NUC:                      ; the nuclei keep their electrons inside the field
  INC NNUC
  LDA #(QMINX+14)
  STA BLX
  LDA #(QMAXX-14)
  STA BHX
  LDA #(QMINY+14)
  STA BLY
  LDA #(QMAXY-14)
  STA BHY
  JMP MB_LIM

MOVE_ELE:
  LDA FRAME_CNT                ; one step of the orbit every 4 frames
  AND #$03
  BNE .me_p
  LDA P_A,X
  CLC
  ADC P_VXL,X
  AND #$1F
  STA P_A,X
.me_p:
  JMP PLACE_ELEC

MOVE_POS:                      ; straight away, gone at the border
  INC NPOS
  JSR MOVE_STRAIGHT
  LDA P_XH,X
  CMP #QMINX
  BCC .mp_off
  CMP #(QMAXX+1)
  BCS .mp_off
  LDA P_YH,X
  CMP #QMINY
  BCC .mp_off
  CMP #(QMAXY+1)
  BCS .mp_off
  RTS
.mp_off:
  STZ P_T,X
  RTS

MOVE_PUL:                      ; one pixel towards the probe (every other frame at first)
  LDA #$01
  STA SND_UFO
  LDA CYCLE
  BNE .mu_go
  LDA FRAME_CNT
  EOR PI
  AND #$01
  BNE .mu_ret
.mu_go:
  LDA PST
  BNE .mu_ret
  LDA P_XH,X
  CMP PRX
  BEQ .mu_y
  BCC .mu_xp
  DEC P_XH,X
  BRA .mu_y
.mu_xp:
  INC P_XH,X
.mu_y:
  LDA P_YH,X
  CMP PRY
  BEQ .mu_ret
  BCC .mu_yp
  DEC P_YH,X
.mu_ret:
  RTS
.mu_yp:
  INC P_YH,X
  RTS

MOVE_SPL:                      ; wanders, then splits into 3 triphons
  DEC P_TM,X
  BNE .ms_w
  JMP SPLIT
.ms_w:
  LDA P_TM,X
  AND #$1F
  BNE MOVE_BOUNCE
  JSR NEXT_RND                 ; new direction
  AND #$0F
  STA P_A,X
  JSR SET_VEL
  ; fall into MOVE_BOUNCE

MOVE_BOUNCE:                   ; straight on, bouncing on the walls
  LDA #QMINX
  STA BLX
  LDA #QMAXX
  STA BHX
  LDA #QMINY
  STA BLY
  LDA #QMAXY
  STA BHY
MB_LIM:                        ; the same inside BLX-BHX, BLY-BHY
  JSR MOVE_STRAIGHT
  LDA P_XH,X
  CMP BLX
  BCC .mb_xn
  CMP BHX
  BCC .mb_y
  BEQ .mb_y
  LDA BHX
  STA P_XH,X
  LDA P_VXH,X
  BMI .mb_y
  BRA .mb_xf
.mb_xn:
  LDA BLX
  STA P_XH,X
  LDA P_VXH,X
  BPL .mb_y
.mb_xf:
  JSR NEG_VX
.mb_y:
  LDA P_YH,X
  CMP BLY
  BCC .mb_yn
  CMP BHY
  BCC .mb_ret
  BEQ .mb_ret
  LDA BHY
  STA P_YH,X
  LDA P_VYH,X
  BMI .mb_ret
  BRA .mb_yf
.mb_yn:
  LDA BLY
  STA P_YH,X
  LDA P_VYH,X
  BPL .mb_ret
.mb_yf:
  JMP NEG_VY
.mb_ret:
  RTS

MOVE_STRAIGHT:
  LDA P_XL,X
  CLC
  ADC P_VXL,X
  STA P_XL,X
  LDA P_XH,X
  ADC P_VXH,X
  STA P_XH,X
  LDA P_YL,X
  CLC
  ADC P_VYL,X
  STA P_YL,X
  LDA P_YH,X
  ADC P_VYH,X
  STA P_YH,X
  RTS

NEG_VX:
  LDA #$00
  SEC
  SBC P_VXL,X
  STA P_VXL,X
  LDA #$00
  SBC P_VXH,X
  STA P_VXH,X
  RTS

NEG_VY:
  LDA #$00
  SEC
  SBC P_VYL,X
  STA P_VYL,X
  LDA #$00
  SBC P_VYH,X
  STA P_VYH,X
  RTS

SPLIT:                         ; splitter X -> 3 triphons, 120 degrees apart
  LDA P_XH,X
  STA PCX
  LDA P_YH,X
  STA PCY
  STZ P_T,X
  LDA #W_SPLIT
  LDY PCX
  JSR SFX_AT
  LDA #T_TRI
  STA PTYPE
  JSR NEXT_RND
  AND #$0F
  STA T3
  LDA #3
  STA T2
.sl_l:
  JSR SPAWN
  BCS .sl_ret
  LDA PCX
  STA P_XH,X
  LDA PCY
  STA P_YH,X
  LDA T3
  STA P_A,X
  JSR SET_VEL
  LDA T3
  CLC
  ADC #5
  AND #$0F
  STA T3
  DEC T2
  BNE .sl_l
.sl_ret:
  LDX PI
  RTS

; particle PI caught: explosion; a nucleus frees its electrons as positrons
KILL_PART:
  STZ EVPOS
  LDX PI
  LDA P_XH,X
  STA PCX
  LDA P_YH,X
  STA PCY
  LDA P_T,X
  STZ P_T,X
  STZ P_CAP,X
  CMP #T_NUC
  BNE .kp_ex
  LDY #(MAXP-1)                ; its electrons fly away
.kp_e:
  LDA P_T,Y
  CMP #T_ELE
  BNE .kp_en
  LDA P_PAR,Y
  CMP PI
  BNE .kp_en
  LDA P_CAP,Y
  BNE .kp_en
  LDA #T_POS
  STA P_T,Y
  LDA P_A,Y                    ; outwards: orbit angle / 2 = direction
  LSR A
  STA P_A,Y
  PHY
  PHY
  PLX
  JSR SET_VEL
  PLY
  LDA #$01
  STA EVPOS
.kp_en:
  DEY
  BPL .kp_e
  LDA EVPOS
  BEQ .kp_ex
  STZ EVPOS
  LDA #W_POS
  LDX #2
  JSR SFX_WHISTLE
.kp_ex:
  JMP NEW_EXPL


; ===============================================================
;  COLLISIONS: probe against the dangerous particles
; ===============================================================
CHECK_HITS:
  LDA PST
  BNE .ch_ret
  LDA INVT
  BNE .ch_ret
  LDX #(MAXP-1)
.ch_l:
  LDY P_T,X
  BEQ .ch_n
  LDA TY_R,Y
  BEQ .ch_n                    ; safe particle
  STA T2
  LDA P_XH,X
  SEC
  SBC PRX
  JSR ABS_A
  CMP T2
  BCS .ch_n
  LDA P_YH,X
  SEC
  SBC PRY
  JSR ABS_A
  CMP T2
  BCC PROBE_DIE
.ch_n:
  DEX
  BPL .ch_l
.ch_ret:
  RTS

PROBE_DIE:
  LDA #$01
  STA PST
  LDA #60
  STA PSTT
  STZ SND_THR
  LDA PRX
  STA PCX
  LDA PRY
  STA PCY
  JSR NEW_EXPL
  LDA #S_BIG
  LDX #2
  JMP SFX_BOOM


; ===============================================================
;  END OF THE WAVE: no nuclei and no positrons left
; ===============================================================
WAVE_CHECK:
  LDA WAVET
  BEQ .wc_test
  DEC WAVET
  RTS
.wc_test:
  LDA PST
  BNE .wc_ret
  LDA NNUC
  ORA NPOS
  BNE .wc_ret
  LDA #70
  STA WAVET
.wc_ret:
  RTS


; ===============================================================
;  SCORE AND HUD
; ===============================================================
ADD_SCORE:
  LDX CURP
  SED
  CLC
  LDA SCA,X
  ADC PTS_L
  STA SCA,X
  LDA SCB,X
  ADC PTS_M
  STA SCB,X
  LDA SCC,X
  ADC PTS_H
  STA SCC,X
  CLD
  CMP NXL,X
  BCC .as_d
  INC LIVES,X                  ; extra probe
  SED
  LDA NXL,X
  CLC
  ADC #$01
  STA NXL,X
  CLD
  LDA #W_LIFE
  LDX #2
  JSR SFX_WHISTLE
  JSR DRAW_LIVES
.as_d:
  JMP DRAW_SCORES

DRAW_HUD:
  LDA #$F1
  STA TCOL
  LDA #0
  STA CELLR
  LDA #13
  STA CELLC
  LDA HIC
  JSR PUT_BCD
  LDA HIB
  JSR PUT_BCD
  LDA HIA
  JSR PUT_BCD
  LDA #<TXT_HNOWAVE            ; "WAVE nn" of the player in the game
  STA TP
  LDA #>TXT_HNOWAVE
  STA TP+1
  LDA PLAYING
  BNE .dh_w
  JSR DRAW_TEXT
  BRA .dh_s
.dh_w:
  LDA #<TXT_HWAVE
  STA TP
  LDA #>TXT_HWAVE
  STA TP+1
  JSR DRAW_TEXT
  LDA #$71
  STA TCOL
  LDA #1
  STA CELLR
  LDA #17
  STA CELLC
  LDX CURP
  LDA WAVE,X
  INC A
  JSR BIN2BCD
  JSR PUT_BCD
.dh_s:
  JSR DRAW_SCORES
  ; fall into DRAW_LIVES

; one '^' per probe under the score (up to 6)
DRAW_LIVES:
  LDA #1
  STA CELLR
  LDX #$00
.dl_p:
  CPX NPL
  BCS .dl_ret
  LDA SCORE_COL,X
  STA CELLC
  LDA #$F1
  STA TCOL
  LDA LIVES,X
  STA T6
  LDA #6
  STA T7
.dl_c:
  LDA #$20
  LDY T6
  BEQ .dl_s
  DEC T6
  LDA #$5E
.dl_s:
  PHX
  JSR PUT_CHAR
  PLX
  INC CELLC
  DEC T7
  BNE .dl_c
  INX
  BRA .dl_p
.dl_ret:
  RTS

DRAW_SCORES:
  LDA #0
  STA CELLR
  LDX #$00
.ds_p:
  CPX NPL
  BCS .ds_ret
  LDA #$E1                     ; grey, white for the player in the game
  CPX CURP
  BNE .ds_c
  LDA #$F1
.ds_c:
  STA TCOL
  LDA SCORE_COL,X
  STA CELLC
  LDA SCC,X
  PHX
  JSR PUT_BCD
  PLX
  LDA SCB,X
  PHX
  JSR PUT_BCD
  PLX
  LDA SCA,X
  PHX
  JSR PUT_BCD
  PLX
  INX
  BRA .ds_p
.ds_ret:
  RTS

CLEAR_MSG:                     ; the wave message goes away
  LDA #<TXT_NOMSG
  STA TP
  LDA #>TXT_NOMSG
  STA TP+1
  JMP DRAW_TEXT


; ===============================================================
;  SCREEN
; ===============================================================
CLEAR_ALL:                     ; HUD black, playfield white on black
  LDA #$11
  STA CLRCOL
  LDA #0
  LDX #2
  JSR CLEAR_ROWS
  ; fall into CLEAR_PLAYFIELD
CLEAR_PLAYFIELD:
  LDA #$F1
  STA CLRCOL
  LDA #2
  LDX #22
  JMP CLEAR_ROWS

DRAW_BORDER:                   ; frame around the playfield
  LDA #BORD_COL
  STA PCOL
  STZ PX
.db_h:
  LDA #16
  STA PY
  JSR PLOT_SET
  LDA #191
  STA PY
  JSR PLOT_SET
  INC PX
  BNE .db_h
  LDA #17
  STA PY
.db_v:
  STZ PX
  JSR PLOT_SET
  LDA #255
  STA PX
  JSR PLOT_SET
  INC PY
  LDA PY
  CMP #191
  BNE .db_v
  RTS


; ===============================================================
;  EXPLOSIONS (sprites)
; ===============================================================
NEW_EXPL:                      ; at (PCX, PCY)
  LDX EXI
  LDA #$01
  STA E_T,X
  LDA PCX
  STA E_X,X
  LDA PCY
  STA E_Y,X
  INX
  CPX #NEXPL
  BCC .ne_s
  LDX #$00
.ne_s:
  STX EXI
  RTS

UPDATE_EXPL:
  LDX #(NEXPL-1)
.ue_l:
  LDA E_T,X
  BEQ .ue_n
  INC E_T,X
  LDA E_T,X
  CMP #16
  BCC .ue_n
  STZ E_T,X
.ue_n:
  DEX
  BPL .ue_l
  RTS


; ===============================================================
;  SPRITES AND NMI
;  0 probe, 1-20 particles (the order turns every frame), 21-24 explosions
; ===============================================================
BUILD_SAT:
  LDA PST                      ; ---- probe (it blinks while it is safe)
  BNE .bs_np
  LDA INVT
  AND #$04
  BNE .bs_np
  LDA PRX
  STA SPX
  LDA PRY
  STA SPY
  LDA FRAME_CNT
  AND #$04
  STA SPN
  LDA #PROBE_COL
  STA SPC
  LDX #0
  JSR SET_SPR
  BRA .bs_parts
.bs_np:
  LDA #HIDE_Y
  STA SAT_BUFFER
.bs_parts:
  LDA RR                       ; ---- particles, starting from RR
  CLC
  ADC #7
  CMP #MAXP
  BCC .bs_rr
  SBC #MAXP
.bs_rr:
  STA RR
  STA T6                       ; particle
  LDA #4
  STA T5                       ; offset in the SAT
.bs_pl:
  LDX T6
  LDY P_T,X
  BEQ .bs_ph
  LDA P_XH,X
  STA SPX
  LDA P_YH,X
  STA SPY
  LDA TY_SPR,Y
  STA SPN
  LDA TY_COL,Y
  STA SPC
  CPY #T_PUL                   ; the pulsar pulses its arms
  BNE .bs_sp
  LDA FRAME_CNT
  AND #$08
  LSR A
  CLC
  ADC SPN
  STA SPN
  BRA .bs_set
.bs_sp:
  CPY #T_SPL                   ; the splitter flashes
  BNE .bs_set
  LDA FRAME_CNT
  LSR A
  LSR A
  AND #$07
  TAY
  LDA SPL_COL,Y
  STA SPC
.bs_set:
  LDX T5
  JSR SET_SPR
  BRA .bs_pn
.bs_ph:
  LDX T5
  LDA #HIDE_Y
  STA SAT_BUFFER,X
.bs_pn:
  LDA T5
  CLC
  ADC #4
  STA T5
  INC T6
  LDA T6
  CMP #MAXP
  BCC .bs_pw
  STZ T6
.bs_pw:
  LDA T5
  CMP #(4+MAXP*4)
  BNE .bs_pl
  LDA #$00                     ; ---- explosions
  STA T6
.bs_el:
  LDX T6
  LDA E_T,X
  BEQ .bs_eh
  LSR A
  LSR A
  ASL A
  ASL A
  CLC
  ADC #44
  STA SPN
  LDA E_X,X
  STA SPX
  LDA E_Y,X
  STA SPY
  LDA #$0B
  STA SPC
  LDA T6
  ASL A
  ASL A
  CLC
  ADC #(4+MAXP*4)
  TAX
  JSR SET_SPR
  BRA .bs_en
.bs_eh:
  LDA T6
  ASL A
  ASL A
  TAX
  LDA #HIDE_Y
  STA SAT_BUFFER+(4+MAXP*4),X
.bs_en:
  INC T6
  LDA T6
  CMP #NEXPL
  BNE .bs_el
  RTS

; 16x16 sprite centred on (SPX, SPY of the playfield), pattern SPN, colour SPC;
; X = offset in SAT_BUFFER. Near the left edge the early clock bit is used.
SET_SPR:
  LDA SPY
  CLC
  ADC #7                       ; + 16 (HUD) - 8 (centre) - 1 (SAT)
  STA SAT_BUFFER,X
  LDA SPN
  STA SAT_BUFFER+2,X
  LDA SPX
  SEC
  SBC #8
  BCC .ss_ec
  STA SAT_BUFFER+1,X
  LDA SPC
  STA SAT_BUFFER+3,X
  RTS
.ss_ec:
  CLC
  ADC #32
  STA SAT_BUFFER+1,X
  LDA SPC
  ORA #$80
  STA SAT_BUFFER+3,X
  RTS

HIDE_SPRITES:
  LDX #(NSPR*4-4)
  LDA #HIDE_Y
.hs_l:
  STA SAT_BUFFER,X
  DEX
  DEX
  DEX
  DEX
  BPL .hs_l
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
  CPX #(NSPR*4+1)         ; NSPR sprites x 4 bytes + Y=$D0 of the next entry
  BNE .copy_sat
  JSR SND_TICK            ; sound effects
  RTS                     ; the BIOS NMI_HANDLER rereads VREG and does RTI

NSPR = 1+MAXP+NEXPL
SAT_BUFFER:
  .dsb NSPR*4,HIDE_Y
  .byte $D0


; ===============================================================
;  SOUND: effects only
;  per chip: A = tone effects / pulsar hum, B = noise (explosions,
;  hiss of the probe), C = thump of the explosions
; ===============================================================
SND_TICK:
  PHA
  PHX
  PHY
  INC SND_PH
  LDA SND_CMD
  BEQ .st_run
  STZ SND_CMD
  JSR SND_GAME_MODE
.st_run:
  JSR SFX_TICK
  JSR AY_FLUSH
  PLY
  PLX
  PLA
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
  ; ---- channel A: tone effect, otherwise the hum of the pulsars
  LDA WH_ID,X
  BEQ .sf_hum
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
.sf_hum:
  LDA SND_UFO
  BEQ .sf_noise
  LDA SND_PH                    ; pulsar: a low throb that goes in and out
  AND #$1F
  JSR TRIANGLE
  ASL A
  ASL A
  CLC
  ADC #150
  STA SH_L,Y
  LDA #$00
  STA SH_L+1,Y
  LDA SND_PH
  AND #$08
  LSR A
  LSR A
  LSR A
  CLC
  ADC #$06
  STA SH_L+8,Y
.sf_noise:
  ; ---- channels B and C: explosion, otherwise the hiss of the probe
  LDX SND_T1
  LDA EX_ID,X
  BEQ .sf_thr
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
.sf_thr:
  LDA SND_THR
  BEQ .sf_next
  LDA SND_RND                   ; the probe moves: a high soft hiss
  AND #$01
  CLC
  ADC #$01
  STA SH_L+6,Y
  LDA #$05
  STA SH_L+9,Y
.sf_next:
  LDX SND_T1
  DEX
  BMI .sf_done
  JMP .sf_chip
.sf_done:
  RTS

TRIANGLE:                       ; A = 0-31 -> 0-15-0
  CMP #$10
  BCC .tr_r
  EOR #$1F
.tr_r:
  RTS

; A = tone effect, Y = X of the object: on its side
SFX_AT:
  LDX #$00
  CPY #$80
  BCC .sa_l
  INX
.sa_l:
  JMP SFX_WHISTLE

; ===============================================================
;  LIBRARY (from lunar_lander): joystick, text, cells, VDP
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

; SAT: 0 lander, 1 flame, 2-5 explosion (2x2 sprites), then Y=$D0 = end of list

; ===============================================================
;  PIXEL (with a copy of the bitmap and of the colours in RAM)
; ===============================================================
; cell / line address: T0 = (x & $F8) | (y & 7), T1 = y / 8
PIX_ADDR:
  LDA PX
  AND #$F8
  STA T0
  LDA PY
  AND #$07
  ORA T0
  STA T0
  LDA PY
  LSR A
  LSR A
  LSR A
  STA T1
  RTS

PLOT_SET:                      ; lights (PX,PY) with colour PCOL
  JSR PIX_ADDR
  LDA PX
  AND #$07
  TAY
  LDA BITMASK,Y
  STA T2
  LDA T0
  STA SPTR
  LDA T1
  CLC
  ADC #>SH_PAT
  STA SPTR+1
  LDA (SPTR)
  ORA T2
  STA (SPTR)
  STA T3
  LDA SPTR+1
  CLC
  ADC #(>SH_COL-(>SH_PAT))
  STA SPTR+1
  LDA PCOL
  STA (SPTR)
  LDA T0
  STA VREG
  LDA T1
  ORA #$40
  STA VREG
  LDA T3
  STA VDATA
  LDA T0
  STA VREG
  LDA T1
  ORA #$60
  STA VREG
  LDA PCOL
  STA VDATA
  RTS

PLOT_CLR:                      ; clears (PX,PY)
  JSR PIX_ADDR
  LDA PX
  AND #$07
  TAY
  LDA BITMASK,Y
  EOR #$FF
  STA T2
  LDA T0
  STA SPTR
  LDA T1
  CLC
  ADC #>SH_PAT
  STA SPTR+1
  LDA (SPTR)
  AND T2
  STA (SPTR)
  STA T3
  LDA T0
  STA VREG
  LDA T1
  ORA #$40
  STA VREG
  LDA T3
  STA VDATA
  RTS


; ===============================================================
;  8x8 CELLS (copy in RAM + VRAM)
; ===============================================================
; from CELLC/CELLR: T0 = col*8, T1 = row, SPTR = pattern in RAM, PTR2 = colours in RAM
CELL_SETUP:
  LDA CELLC
  ASL A
  ASL A
  ASL A
  STA T0
  STA SPTR
  STA PTR2
  LDA CELLR
  STA T1
  CLC
  ADC #>SH_PAT
  STA SPTR+1
  LDA T1
  CLC
  ADC #>SH_COL
  STA PTR2+1
  RTS

; copies the cell (copy in RAM) into the VRAM: needs CELL_SETUP
FLUSH_CELL:
  LDA T0
  STA VREG
  LDA T1
  ORA #$40
  STA VREG
  LDY #$00
.fl_p:
  LDA (SPTR),Y
  STA VDATA
  INY
  CPY #$08
  BNE .fl_p
  LDA T0
  STA VREG
  LDA T1
  ORA #$60
  STA VREG
  LDY #$00
.fl_c:
  LDA (PTR2),Y
  STA VDATA
  INY
  CPY #$08
  BNE .fl_c
  RTS

; draws the tile at PTR (8 pattern + 8 colour bytes) in (CELLC,CELLR); PTR moves on by 16
BLIT_CELL:
  JSR CELL_SETUP
  LDY #$00
.bl_p:
  LDA (PTR),Y
  STA (SPTR),Y
  INY
  CPY #$08
  BNE .bl_p
  LDA PTR
  CLC
  ADC #$08
  STA PTR
  BCC .bl_n1
  INC PTR+1
.bl_n1:
  LDY #$00
.bl_c:
  LDA (PTR),Y
  STA (PTR2),Y
  INY
  CPY #$08
  BNE .bl_c
  LDA PTR
  CLC
  ADC #$08
  STA PTR
  BCC .bl_n2
  INC PTR+1
.bl_n2:
  JMP FLUSH_CELL

; A = ASCII code ($20-$5F), in (CELLC,CELLR) with colour TCOL
PUT_CHAR:
  SEC
  SBC #$20
  AND #$3F
  STA T4
  LDA #$00
  STA T5
  ASL T4
  ROL T5
  ASL T4
  ROL T5
  ASL T4
  ROL T5
  LDA T4
  CLC
  ADC #<FONT
  STA PTR
  LDA T5
  ADC #>FONT
  STA PTR+1
  JSR CELL_SETUP
  LDY #$00
.pc_l:
  LDA (PTR),Y
  STA (SPTR),Y
  LDA TCOL
  STA (PTR2),Y
  INY
  CPY #$08
  BNE .pc_l
  JMP FLUSH_CELL

; A = BCD byte: two digits, CELLC moves on by 2
PUT_BCD:
  PHA
  LSR A
  LSR A
  LSR A
  LSR A
  ORA #$30
  JSR PUT_CHAR
  INC CELLC
  PLA
  AND #$0F
  ORA #$30
  JSR PUT_CHAR
  INC CELLC
  RTS

; record: row, column, colour (fg), characters..., 0   (end of the list: row = $FF)
DRAW_TEXT:
  LDY #$00
  LDA (TP),Y
  CMP #$FF
  BEQ .dt_end
  STA CELLR
  INY
  LDA (TP),Y
  STA CELLC
  INY
  LDA (TP),Y
  ASL A
  ASL A
  ASL A
  ASL A
  ORA #$01
  STA TCOL
  INY
.dt_ch:
  LDA (TP),Y
  BEQ .dt_next
  STY TYV
  JSR PUT_CHAR
  LDY TYV
  INC CELLC
  INY
  BRA .dt_ch
.dt_next:
  INY
  TYA
  CLC
  ADC TP
  STA TP
  BCC DRAW_TEXT
  INC TP+1
  BRA DRAW_TEXT
.dt_end:
  RTS

; big words: row, column, n, letter ids... (end of the list: row = $FF)
DRAW_BIGWORDS:
  LDY #$00
  LDA (TP),Y
  CMP #$FF
  BEQ .bw_end
  STA CELLR
  INY
  LDA (TP),Y
  STA CELLC
  INY
  LDA (TP),Y
  STA T7                       ; number of letters
  INY
.bw_l:
  LDA (TP),Y
  STY TYV
  JSR BIGLET
  LDY TYV
  INC CELLC
  INC CELLC
  INY
  DEC T7
  BNE .bw_l
  TYA
  CLC
  ADC TP
  STA TP
  BCC DRAW_BIGWORDS
  INC TP+1
  BRA DRAW_BIGWORDS
.bw_end:
  RTS

BIGLET:                        ; A = lettera, in (CELLC,CELLR), 2x2 tile
  STA T4
  LDA #$00
  STA T5
  LDY #$06
.bg_sh:
  ASL T4
  ROL T5
  DEY
  BNE .bg_sh
  LDA T4
  CLC
  ADC #<BIGFONT
  STA PTR
  LDA T5
  ADC #>BIGFONT
  STA PTR+1
  LDA CELLC
  STA BIGC
  LDA CELLR
  STA BIGR
  JSR BLIT_CELL
  INC CELLC
  JSR BLIT_CELL
  LDA BIGC
  STA CELLC
  INC CELLR
  JSR BLIT_CELL
  INC CELLC
  JSR BLIT_CELL
  LDA BIGC
  STA CELLC
  LDA BIGR
  STA CELLR
  RTS



; first row in A, number of rows in X: clears the patterns, colours = CLRCOL
CLEAR_ROWS:
  STA T0
  STX T1
  LDA #$00
  STA SPTR
  STA PTR2
  LDA T0
  CLC
  ADC #>SH_PAT
  STA SPTR+1
  LDA T0
  CLC
  ADC #>SH_COL
  STA PTR2+1
  LDX T1
.cr_pg:
  LDY #$00
.cr_by:
  LDA #$00
  STA (SPTR),Y
  LDA CLRCOL
  STA (PTR2),Y
  INY
  BNE .cr_by
  INC SPTR+1
  INC PTR2+1
  DEX
  BNE .cr_pg
  LDA #$00
  STA VREG
  LDA T0
  ORA #$40
  STA VREG
  LDX T1
.cr_vp:
  LDY #$00
.cr_vpb:
  LDA #$00
  STA VDATA
  INY
  BNE .cr_vpb
  DEX
  BNE .cr_vp
  LDA #$00
  STA VREG
  LDA T0
  ORA #$60
  STA VREG
  LDX T1
.cr_vc:
  LDY #$00
.cr_vcb:
  LDA CLRCOL
  STA VDATA
  INY
  BNE .cr_vcb
  DEX
  BNE .cr_vc
  RTS

CLEAR_SCREEN:
  LDA #$00
  LDX #24
  JMP CLEAR_ROWS


; name table: tile = position (0-255 in each of the 3 thirds) => full bitmap
INIT_NAME_TABLE:
  LDA #<VDP_NAME_TABLE_BASE
  STA VREG
  LDA #(VDP_WRITE_VRAM_BIT | >VDP_NAME_TABLE_BASE)
  STA VREG
  LDX #$03
.in_p:
  LDY #$00
.in_b:
  TYA
  STA VDATA
  INY
  BNE .in_b
  DEX
  BNE .in_p
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
;  TABLES
; ===============================================================
; by particle type: -, nucleus, electron, positron, photon, pulsar, splitter, triphon, tryd
TY_SPR:     .byte 0,8,12,16,20,24,32,36,40          ; sprite pattern
TY_COL:     .byte 0,$0D,$07,$09,$03,$0B,$0F,$0F,$05 ; sprite colour
TY_R:       .byte 0,8,0,0,7,8,7,7,7                 ; collision distance (0 = safe)
TY_PL:      .byte 0,$00,$20,$00,$00,$00,$00,$00,$00 ; points (BCD)
TY_PM:      .byte 0,$03,$00,$02,$02,$04,$01,$01,$03
TY_CLS:     .byte 0,0,0,4,2,0,1,3,1                 ; speed class (VEL_* tables)
SPL_COL:    .byte $08,$0B,$0D,$0F,$03,$07,$09,$0A   ; flashing splitter
SCORE_COL:  .byte 1,25                              ; score and probes of player 1 / 2

; the 8 waves (then again, faster): nuclei, electrons per nucleus, photons,
; pulsars, splitters, tryds, triphons
WV_NUC:     .byte 1,2,2,2,3,3,3,4
WV_EPN:     .byte 3,2,3,2,2,3,3,2
WV_PHO:     .byte 0,1,1,1,1,1,2,1
WV_PUL:     .byte 0,0,0,1,0,1,0,1
WV_SPL:     .byte 0,0,0,0,1,0,1,1
WV_TRY:     .byte 0,0,1,0,0,1,0,1
WV_TRI:     .byte 0,0,0,0,0,0,1,0
; angles of the electrons on the orbit (by number of electrons)
EANG_BASE:  .byte 0,0,1,3
EANG:       .byte 0, 0,16, 0,11,21

; title: the table of the particles (sprite beside every line)
TT_T:       .byte 1,2,3,4,5,6,7,8
TT_X:       .byte 36,36,36,36,152,152,152,152
TT_Y:       .byte 59,75,91,107,59,75,91,107

; text records: row, column, colour, characters, 0   (end of list: $FF)
TXT_TITLE:
  .byte 7,5,15,"ENCIRCLE THE PARTICLES",0
  .byte 9,6,13,"NUCLEUS  300",0
  .byte 11,6,7,"ELECTRON  20",0
  .byte 13,6,9,"POSITRON 200",0
  .byte 15,6,3,"PHOTON   200",0
  .byte 9,20,11,"PULSAR   400",0
  .byte 11,20,15,"SPLITTER 100",0
  .byte 13,20,15,"TRIPHON  100",0
  .byte 15,20,5,"TRYD     300",0
  .byte 17,2,14,"SEVERAL IN ONE LOOP X2 X3 X4",0
  .byte 19,6,15,"BUTTON 1 = 1 PLAYER",0
  .byte 21,6,15,"BUTTON 2 = 2 PLAYERS",0
  .byte 23,1,14,"JOYSTICK MOVES  BUTTON BRAKES",0
  .byte $FF
TXT_PLAYER:
  .byte 7,12,11,"PLAYER",0
  .byte $FF
TXT_WAVE:
  .byte 9,12,15,"WAVE",0
  .byte $FF
TXT_HWAVE:
  .byte 1,12,7,"WAVE",0
  .byte $FF
TXT_HNOWAVE:
  .byte 1,12,7,"       ",0
  .byte $FF
TXT_NOMSG:
  .byte 7,12,15,"        ",0
  .byte 9,12,15,"        ",0
  .byte $FF
TXT_PRESS:
  .byte 16,9,15,"PRESS A BUTTON",0
  .byte $FF
; big words: row, column, number of letters, letters (Q U A N T M G E O V R)
TITLE_BIG:
  .byte 3,9,7,0,1,2,3,4,1,5      ; QUANTUM
  .byte $FF
OVER_BIG:
  .byte 9,12,4,6,2,5,7           ; GAME
  .byte 12,12,4,8,9,7,10         ; OVER
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
; big letters (16x16, 4 tiles each, 8 pattern + 8 colour bytes): Q U A N T M G E O V R
BIGFONT:
  ; Q
  .byte $00,$07,$07,$18,$18,$18,$18,$18,$71,$71,$71,$71,$71,$71,$71,$71
  .byte $00,$E0,$E0,$18,$18,$18,$18,$18,$71,$71,$71,$71,$71,$71,$71,$71
  .byte $18,$19,$19,$18,$18,$07,$07,$00,$51,$51,$51,$51,$51,$51,$51,$51
  .byte $18,$98,$98,$60,$60,$98,$98,$00,$51,$51,$51,$51,$51,$51,$51,$51
  ; U
  .byte $00,$18,$18,$18,$18,$18,$18,$18,$71,$71,$71,$71,$71,$71,$71,$71
  .byte $00,$18,$18,$18,$18,$18,$18,$18,$71,$71,$71,$71,$71,$71,$71,$71
  .byte $18,$18,$18,$18,$18,$07,$07,$00,$51,$51,$51,$51,$51,$51,$51,$51
  .byte $18,$18,$18,$18,$18,$E0,$E0,$00,$51,$51,$51,$51,$51,$51,$51,$51
  ; A
  .byte $00,$01,$01,$06,$06,$18,$18,$18,$71,$71,$71,$71,$71,$71,$71,$71
  .byte $00,$80,$80,$60,$60,$18,$18,$18,$71,$71,$71,$71,$71,$71,$71,$71
  .byte $18,$1F,$1F,$18,$18,$18,$18,$00,$51,$51,$51,$51,$51,$51,$51,$51
  .byte $18,$F8,$F8,$18,$18,$18,$18,$00,$51,$51,$51,$51,$51,$51,$51,$51
  ; N
  .byte $00,$18,$18,$18,$18,$1E,$1E,$19,$71,$71,$71,$71,$71,$71,$71,$71
  .byte $00,$18,$18,$18,$18,$18,$18,$98,$71,$71,$71,$71,$71,$71,$71,$71
  .byte $19,$18,$18,$18,$18,$18,$18,$00,$51,$51,$51,$51,$51,$51,$51,$51
  .byte $98,$78,$78,$18,$18,$18,$18,$00,$51,$51,$51,$51,$51,$51,$51,$51
  ; T
  .byte $00,$1F,$1F,$01,$01,$01,$01,$01,$71,$71,$71,$71,$71,$71,$71,$71
  .byte $00,$F8,$F8,$80,$80,$80,$80,$80,$71,$71,$71,$71,$71,$71,$71,$71
  .byte $01,$01,$01,$01,$01,$01,$01,$00,$51,$51,$51,$51,$51,$51,$51,$51
  .byte $80,$80,$80,$80,$80,$80,$80,$00,$51,$51,$51,$51,$51,$51,$51,$51
  ; M
  .byte $00,$18,$18,$1E,$1E,$19,$19,$19,$71,$71,$71,$71,$71,$71,$71,$71
  .byte $00,$18,$18,$78,$78,$98,$98,$98,$71,$71,$71,$71,$71,$71,$71,$71
  .byte $19,$18,$18,$18,$18,$18,$18,$00,$51,$51,$51,$51,$51,$51,$51,$51
  .byte $98,$18,$18,$18,$18,$18,$18,$00,$51,$51,$51,$51,$51,$51,$51,$51
  ; G
  .byte $00,$07,$07,$18,$18,$18,$18,$18,$71,$71,$71,$71,$71,$71,$71,$71
  .byte $00,$F8,$F8,$00,$00,$00,$00,$00,$71,$71,$71,$71,$71,$71,$71,$71
  .byte $18,$18,$18,$18,$18,$07,$07,$00,$51,$51,$51,$51,$51,$51,$51,$51
  .byte $00,$78,$78,$18,$18,$F8,$F8,$00,$51,$51,$51,$51,$51,$51,$51,$51
  ; E
  .byte $00,$1F,$1F,$18,$18,$18,$18,$1F,$71,$71,$71,$71,$71,$71,$71,$71
  .byte $00,$F8,$F8,$00,$00,$00,$00,$E0,$71,$71,$71,$71,$71,$71,$71,$71
  .byte $1F,$18,$18,$18,$18,$1F,$1F,$00,$51,$51,$51,$51,$51,$51,$51,$51
  .byte $E0,$00,$00,$00,$00,$F8,$F8,$00,$51,$51,$51,$51,$51,$51,$51,$51
  ; O
  .byte $00,$07,$07,$18,$18,$18,$18,$18,$71,$71,$71,$71,$71,$71,$71,$71
  .byte $00,$E0,$E0,$18,$18,$18,$18,$18,$71,$71,$71,$71,$71,$71,$71,$71
  .byte $18,$18,$18,$18,$18,$07,$07,$00,$51,$51,$51,$51,$51,$51,$51,$51
  .byte $18,$18,$18,$18,$18,$E0,$E0,$00,$51,$51,$51,$51,$51,$51,$51,$51
  ; V
  .byte $00,$18,$18,$18,$18,$18,$18,$18,$71,$71,$71,$71,$71,$71,$71,$71
  .byte $00,$18,$18,$18,$18,$18,$18,$18,$71,$71,$71,$71,$71,$71,$71,$71
  .byte $18,$06,$06,$06,$06,$01,$01,$00,$51,$51,$51,$51,$51,$51,$51,$51
  .byte $18,$60,$60,$60,$60,$80,$80,$00,$51,$51,$51,$51,$51,$51,$51,$51
  ; R
  .byte $00,$1F,$1F,$18,$18,$18,$18,$1F,$71,$71,$71,$71,$71,$71,$71,$71
  .byte $00,$E0,$E0,$18,$18,$18,$18,$E0,$71,$71,$71,$71,$71,$71,$71,$71
  .byte $1F,$19,$19,$18,$18,$18,$18,$00,$51,$51,$51,$51,$51,$51,$51,$51
  .byte $E0,$80,$80,$60,$60,$18,$18,$00,$51,$51,$51,$51,$51,$51,$51,$51

; sprites 16x16: probe (2), nucleus, electron, positron, photon, pulsar (2), splitter, triphon, tryd, 4 explosion frames, capture ring
SPR_PAGES = 2
SPRITES:
  .byte $00,$00,$00,$00,$00,$01,$02,$04,$0A,$04,$02,$01,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$80,$40,$A0,$10,$A8,$10,$A0,$40,$80,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$01,$02,$05,$08,$05,$02,$01,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$80,$40,$20,$50,$88,$50,$20,$40,$80,$00,$00,$00
  .byte $00,$00,$00,$00,$03,$07,$0F,$0F,$0F,$0F,$0F,$07,$03,$00,$00,$00
  .byte $00,$00,$00,$00,$E0,$F0,$F8,$F8,$F8,$F8,$F8,$F0,$E0,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$01,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$80,$C0,$80,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$03,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$80,$80,$E0,$80,$80,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$01,$01,$02,$02,$04,$04,$08,$08,$1F,$00,$00,$00
  .byte $00,$00,$00,$80,$40,$40,$20,$20,$10,$10,$08,$08,$FC,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$01,$01,$0F,$78,$07,$01,$01,$01,$00,$00,$00
  .byte $00,$80,$80,$80,$C0,$40,$40,$70,$0F,$78,$40,$40,$80,$80,$80,$80
  .byte $00,$00,$00,$00,$00,$00,$01,$03,$0C,$03,$01,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$80,$80,$40,$60,$18,$60,$40,$80,$80,$00,$00,$00
  .byte $00,$00,$00,$00,$0F,$0C,$0A,$09,$08,$09,$0A,$0C,$0F,$00,$00,$00
  .byte $00,$00,$00,$00,$F8,$18,$28,$48,$88,$48,$28,$18,$F8,$00,$00,$00
  .byte $00,$00,$00,$00,$01,$02,$04,$08,$10,$08,$04,$02,$01,$00,$00,$00
  .byte $00,$00,$00,$80,$40,$20,$90,$88,$84,$88,$90,$20,$40,$80,$00,$00
  .byte $00,$00,$00,$00,$01,$01,$01,$02,$02,$04,$0C,$1F,$08,$00,$00,$00
  .byte $00,$00,$00,$80,$C0,$C0,$40,$20,$20,$10,$18,$FC,$08,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$01,$01,$01,$01,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$C0,$20,$C0,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$02,$02,$04,$02,$00,$01,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$60,$00,$00,$08,$60,$40,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$04,$04,$00,$08,$00,$06,$00,$00,$02,$00,$00
  .byte $00,$00,$00,$00,$00,$40,$10,$00,$00,$02,$00,$20,$50,$00,$00,$00
  .byte $00,$00,$00,$00,$04,$00,$10,$00,$20,$00,$08,$04,$00,$00,$00,$02
  .byte $00,$00,$00,$00,$20,$08,$00,$00,$00,$00,$00,$00,$20,$10,$20,$00
  .byte $00,$00,$07,$18,$10,$20,$20,$20,$20,$20,$20,$20,$10,$18,$07,$00
  .byte $00,$00,$F0,$0C,$04,$02,$02,$02,$01,$02,$02,$02,$04,$0C,$70,$80

; velocities: speed class (0.5 0.75 1 1.25 1.5 2 px per frame) * 16 + direction (0 = up, clockwise), 8.8 signed
VEL_XL:
  .byte $00,$31,$5B,$76,$80,$76,$5B,$31,$00,$CF,$A5,$8A,$80,$8A,$A5,$CF
  .byte $00,$49,$88,$B1,$C0,$B1,$88,$49,$00,$B7,$78,$4F,$40,$4F,$78,$B7
  .byte $00,$62,$B5,$ED,$00,$ED,$B5,$62,$00,$9E,$4B,$13,$00,$13,$4B,$9E
  .byte $00,$7A,$E2,$28,$40,$28,$E2,$7A,$00,$86,$1E,$D8,$C0,$D8,$1E,$86
  .byte $00,$93,$10,$63,$80,$63,$10,$93,$00,$6D,$F0,$9D,$80,$9D,$F0,$6D
  .byte $00,$C4,$6A,$D9,$00,$D9,$6A,$C4,$00,$3C,$96,$27,$00,$27,$96,$3C
VEL_XH:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$FF,$FF,$FF,$FF,$FF,$FF,$FF
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$FF,$FF,$FF,$FF,$FF,$FF,$FF
  .byte $00,$00,$00,$00,$01,$00,$00,$00,$00,$FF,$FF,$FF,$FF,$FF,$FF,$FF
  .byte $00,$00,$00,$01,$01,$01,$00,$00,$00,$FF,$FF,$FE,$FE,$FE,$FF,$FF
  .byte $00,$00,$01,$01,$01,$01,$01,$00,$00,$FF,$FE,$FE,$FE,$FE,$FE,$FF
  .byte $00,$00,$01,$01,$02,$01,$01,$00,$00,$FF,$FE,$FE,$FE,$FE,$FE,$FF
VEL_YL:
  .byte $80,$8A,$A5,$CF,$00,$31,$5B,$76,$80,$76,$5B,$31,$00,$CF,$A5,$8A
  .byte $40,$4F,$78,$B7,$00,$49,$88,$B1,$C0,$B1,$88,$49,$00,$B7,$78,$4F
  .byte $00,$13,$4B,$9E,$00,$62,$B5,$ED,$00,$ED,$B5,$62,$00,$9E,$4B,$13
  .byte $C0,$D8,$1E,$86,$00,$7A,$E2,$28,$40,$28,$E2,$7A,$00,$86,$1E,$D8
  .byte $80,$9D,$F0,$6D,$00,$93,$10,$63,$80,$63,$10,$93,$00,$6D,$F0,$9D
  .byte $00,$27,$96,$3C,$00,$C4,$6A,$D9,$00,$D9,$6A,$C4,$00,$3C,$96,$27
VEL_YH:
  .byte $FF,$FF,$FF,$FF,$00,$00,$00,$00,$00,$00,$00,$00,$00,$FF,$FF,$FF
  .byte $FF,$FF,$FF,$FF,$00,$00,$00,$00,$00,$00,$00,$00,$00,$FF,$FF,$FF
  .byte $FF,$FF,$FF,$FF,$00,$00,$00,$00,$01,$00,$00,$00,$00,$FF,$FF,$FF
  .byte $FE,$FE,$FF,$FF,$00,$00,$00,$01,$01,$01,$00,$00,$00,$FF,$FF,$FE
  .byte $FE,$FE,$FE,$FF,$00,$00,$01,$01,$01,$01,$01,$00,$00,$FF,$FE,$FE
  .byte $FE,$FE,$FE,$FF,$00,$00,$01,$01,$02,$01,$01,$00,$00,$FF,$FE,$FE

; orbit of the electrons around the nucleus: 32 steps, radius 13 pixels (signed)
ORBX:
  .byte $00,$03,$05,$07,$09,$0B,$0C,$0D,$0D,$0D,$0C,$0B,$09,$07,$05,$03
  .byte $00,$FD,$FB,$F9,$F7,$F5,$F4,$F3,$F3,$F3,$F4,$F5,$F7,$F9,$FB,$FD
ORBY:
  .byte $F3,$F3,$F4,$F5,$F7,$F9,$FB,$FD,$00,$03,$05,$07,$09,$0B,$0C,$0D
  .byte $0D,$0D,$0C,$0B,$09,$07,$05,$03,$00,$FD,$FB,$F9,$F7,$F5,$F4,$F3

; one-shot tone effects: period and volume for every frame
WH_TL:
  .byte $00,$FA,$B6,$8F,$76,$65,$58,$4D,$45,$3F,$3A,$35,$31,$2E,$2B,$28
  .byte $26,$24,$22,$21,$1F,$1E,$1C,$18,$19,$1B,$1D,$1F,$21,$1B,$1D,$20
  .byte $22,$26,$2A,$77,$77,$77,$77,$77,$77,$5F,$5F,$5F,$5F,$5F,$5F,$50
  .byte $50,$50,$50,$50,$50,$3C,$3C,$3C,$3C,$3C,$3C,$50,$50,$50,$50,$50
  .byte $50,$3C,$3C,$3C,$3C,$3C,$3C,$24,$24,$24,$24,$24,$00,$00,$00,$00
  .byte $24,$24,$24,$24,$24,$00,$00,$00,$00,$24,$24,$24,$24,$24,$45,$3B
  .byte $33,$2D,$00,$00,$00,$39,$30,$2A,$25,$00,$00,$00,$30,$29,$23,$1F
  .byte $59,$53,$4D,$48,$43,$3F,$3C,$39
WH_TH:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
WH_VOL:
  .byte $00,$0E,$0E,$0D,$0D,$0D,$0D,$0C,$0C,$0C,$0B,$0B,$0B,$0B,$0A,$0A
  .byte $0A,$09,$09,$09,$09,$08,$08,$0C,$0B,$0B,$0A,$0A,$09,$0B,$0A,$09
  .byte $08,$07,$06,$0D,$0C,$0C,$0B,$0B,$0A,$0D,$0C,$0C,$0B,$0B,$0A,$0D
  .byte $0C,$0C,$0B,$0B,$0A,$0D,$0C,$0C,$0B,$0B,$0A,$0D,$0C,$0C,$0B,$0B
  .byte $0A,$0D,$0C,$0C,$0B,$0B,$0A,$0D,$0C,$0B,$0A,$09,$00,$00,$00,$00
  .byte $0D,$0C,$0B,$0A,$09,$00,$00,$00,$00,$0D,$0C,$0B,$0A,$09,$0C,$0B
  .byte $0B,$0A,$00,$00,$00,$0C,$0B,$0B,$0A,$00,$00,$00,$0C,$0B,$0A,$09
  .byte $0A,$09,$09,$08,$07,$06,$06,$05
WH_START:
  .byte $00,$01,$17,$23,$47,$5E,$70
WH_LEN:
  .byte $00,$16,$0C,$24,$17,$12,$08
W_CAPT = 1
W_POS = 2
W_WAVE = 3
W_LIFE = 4
W_SPLIT = 5
W_LOOP = 6

; explosions: noise volume / period, low tone volume / period for every frame
EX_NV:
  .byte $00,$0D,$0D,$0C,$0B,$0A,$0A,$09,$08,$07,$07,$06,$05,$04,$04,$03
  .byte $02,$01,$01,$0E,$0E,$0D,$0D,$0C,$0C,$0B,$0B,$0A,$0A,$09,$08,$08
  .byte $07,$07,$06,$06,$05,$05,$04,$03,$03,$02,$02,$01,$01,$0F,$0F,$0F
  .byte $0F,$0F,$0F,$0E,$0E,$0E,$0E,$0E,$0D,$0D,$0D,$0D,$0D,$0C,$0C,$0C
  .byte $0C,$0C,$0C,$0B,$0B,$0B,$0B,$0B,$0A,$0A,$0A,$0A,$0A,$09,$09,$09
  .byte $09,$09,$08,$08,$08,$08,$08,$08,$07,$07,$07,$07,$07,$06,$06,$06
  .byte $06,$06,$05,$05,$05,$05,$05,$04,$04,$04,$04,$04,$04,$03,$03,$03
  .byte $03,$03,$02,$02,$02,$02,$02,$01,$01,$01,$01,$01,$00
EX_NP:
  .byte $00,$04,$04,$04,$04,$05,$05,$05,$05,$06,$06,$06,$06,$07,$07,$07
  .byte $07,$08,$08,$09,$09,$09,$09,$09,$09,$09,$09,$09,$09,$09,$09,$09
  .byte $09,$09,$09,$09,$09,$09,$09,$09,$09,$09,$09,$09,$09,$12,$12,$12
  .byte $12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$13,$13,$13
  .byte $13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$14,$14,$14
  .byte $14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$15,$15,$15
  .byte $15,$15,$15,$15,$15,$15,$15,$15,$15,$15,$15,$15,$15,$16,$16,$16
  .byte $16,$16,$16,$16,$16,$16,$16,$16,$16,$16,$16,$16,$16
EX_VC:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$0B,$0A,$09,$08,$07,$06,$05,$04,$03,$02,$01,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$0D,$0D,$0D
  .byte $0C,$0C,$0C,$0B,$0B,$0B,$0A,$0A,$0A,$09,$09,$09,$08,$08,$08,$07
  .byte $07,$07,$06,$06,$06,$05,$05,$05,$04,$04,$04,$03,$03,$03,$02,$02
  .byte $02,$01,$01,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
EX_TL:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$B6,$B6,$B6,$B6,$B6,$B6,$B6,$B6,$B6,$B6,$B6,$B6,$B6
  .byte $B6,$B6,$B6,$B6,$B6,$B6,$B6,$B6,$B6,$B6,$B6,$B6,$B6,$12,$19,$20
  .byte $27,$2E,$36,$3D,$45,$4C,$54,$5C,$64,$6C,$75,$7D,$85,$8E,$97,$A0
  .byte $A9,$B2,$BB,$C5,$CE,$D8,$E2,$EC,$F6,$01,$0B,$16,$21,$2C,$37,$43
  .byte $4F,$5B,$67,$73,$80,$8C,$99,$A7,$B4,$C2,$D0,$DE,$ED,$FC,$0B,$1B
  .byte $2A,$3A,$4B,$5C,$6D,$7E,$90,$A2,$B5,$C8,$DC,$F0,$04,$19,$2E,$44
  .byte $5B,$71,$89,$A1,$BA,$D3,$ED,$08,$23,$3F,$5C,$7A,$99
EX_TH:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02
  .byte $02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$04,$04,$04
  .byte $04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04
  .byte $04,$04,$04,$04,$04,$04,$04,$04,$04,$05,$05,$05,$05,$05,$05,$05
  .byte $05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$06,$06
  .byte $06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$07,$07,$07,$07
  .byte $07,$07,$07,$07,$07,$07,$07,$08,$08,$08,$08,$08,$08
EX_START:
  .byte $00,$01,$13,$2D
EX_LEN:
  .byte $00,$12,$1A,$50
S_SMALL = 1
S_MED = 2
S_PROBE = 3
S_BIG = S_PROBE
