;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;                                                              ;
;   ARCADE_LUNAR_LANDER  -  land the module on the moon pads   ;
;   65C02 assembly, TMS9918A Graphics II (bitmap 256x192)      ;
;   Base: 1vs1 / missile command (NMI + trampoline $0FD0,      ;
;   joystick VIA, bitmap shadow in RAM, AY sound engine)       ;
;                                                              ;
;   - joystick 1 ($D581) or joystick 2 ($D580):                ;
;       LEFT / RIGHT = rotate the lander                       ;
;       UP or any button = main engine (burns fuel)            ;
;   - land softly on a flat pad: speed under the limit, ship   ;
;     almost upright, both feet on the pad. Small pads pay     ;
;     more (X2 .. X5 multiplier) + leftover fuel bonus         ;
;   - 6 different moon maps, gravity grows, fuel shrinks       ;
;   - 3 landers; a crash costs one; game over when none left   ;
;   - SOUND (2 x AY-3-8910, engine of the other games, played  ;
;     from the NMI at 60 Hz):                                  ;
;       short intro tune on the title, engine roar, rotation   ;
;       ticks (left chip / right chip), low fuel beeps, out    ;
;       of fuel, overspeed alarm, touchdown thud, victory      ;
;       fanfare, crash explosion + sting, game over music      ;
;   - the main loop writes the VDP only with the interrupt     ;
;     off (VDP_INT_OFF just after the NMI); the NMI only       ;
;     copies the SAT during the vblank and plays the sound     ;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; ---------------- zero page ----------------
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
PX          = $7B      ; pixel to draw
PY          = $7C
PCOL        = $7D
P_JOY       = $7E      ; 2 bytes (joystick, 1 = pressed)
JOYC        = $80      ; joystick 1 OR joystick 2
ANG         = $81      ; lander angle 0-15 (0 = up, 22.5 degrees per step, + = clockwise)
ROTT        = $82      ; rotation repeat timer
POSXL       = $83      ; position 8.8 (centre of the lander)
POSXH       = $84
POSYL       = $85
POSYH       = $86
VXL         = $87      ; velocity 8.8 signed, px per frame (VY must follow VX)
VXH         = $88
VYL         = $89
VYH         = $8A
FUELL       = $8B
FUELH       = $8C
THR         = $8D      ; 1 = engine on this frame
STATE       = $8E      ; 0 flying, 1 landed, 2 crashed
LEVEL       = $8F
LIVES       = $90
SCORE       = $91      ; 3 bytes BCD (low, mid, high)
HISCORE     = $94      ; 3 bytes BCD
MULT        = $97      ; multiplier of the pad
HUDT        = $98
EXF         = $99      ; explosion frame
EXT         = $9A
GRAV        = $9B
LOWT        = $9C      ; low fuel beep timer
ALMT        = $9D      ; overspeed alarm timer
ADLO        = $9E
ADMID       = $9F
REASON      = $A0      ; crash reason 1 speed, 2 angle, 3 rocks
TYV         = $A1
BIGC        = $A2
BIGR        = $A3
SND_THR     = $A4      ; 1 = engine roar (read by the NMI)
PPL         = $A5      ; 2 bytes: pad table of the level
PADI        = $A7
LVI         = $A8      ; terrain index of the level (0-5)

; ---------------- sound: two AY-3-8910, 1 MHz clock ----------------
AY_R_LATCH = $D380       ; right AY
AY_R_WRITE = $D381
AY_L_LATCH = $D384       ; left AY
AY_L_WRITE = $D385

SN1        = $BB         ; sound temporaries (NMI only)
SND_T1     = $BC
SH_L       = $C0         ; shadow of AY left registers 0-10 (11 bytes)
SH_R       = $D0         ; shadow of AY right registers 0-10 (SH_R = SH_L + 16)
TR_PL      = $DC         ; 4 tracks: pointer (lo / hi), counter, active,
TR_PH      = $E0         ;           note, volume, note age
TR_CT      = $E4
TR_ACT     = $E8
TR_NOTE    = $EC
TR_VOL     = $F0
TR_AGE     = $F4
SND_PTR    = $F8         ; 2 bytes
SND_CMD    = $FA         ; command to the sound engine (CMD_*), run by the NMI
SND_MODE   = $FB         ; 0 = game effects, 1 = music
SND_BUSY   = $FC         ; 1 while a song is playing
SND_PH     = $FD
SND_RND    = $FE
SN0        = $FF

WH_ID      = $0700       ; tone effect playing per chip (0 = none)  2 bytes
WH_POS     = $0702       ; frames elapsed
EX_ID      = $0704       ; explosion playing per chip (0 none, 1 small, 2 big, 3 thud)
EX_POS     = $0706
SMT0       = $0708       ; temporaries, main loop side
SMT1       = $0709

CMD_GAME   = 1           ; silence + game effects
CMD_TITLE  = 2           ; title tune
CMD_LOSE   = 3           ; game over music
CMD_WIN    = 4           ; landing fanfare
CMD_CRASH  = 5           ; crash sting
S_SMALL    = 1
S_BIG      = 2
S_THUD     = 3

; ---------------- RAM arrays ----------------
TERR   = $0800           ; ground height (Y of the surface) for every X
PADM   = $0900           ; pad multiplier for every X (0 = rock)
SH_PAT = $4000           ; copy of the screen (pattern) in RAM
SH_COL = $6000           ; copy of the colours

; ---------------- parameters ----------------
THRUST_MAX  = 14         ; engine acceleration (1/256 px per frame^2)
VY_MAX      = 160        ; safe landing speed (1/256 px per frame)
VX_MAX      = 100
ROT_DELAY   = 3          ; frames between two rotation steps
BTN_MASK    = %00110000
HIDE_Y      = $C0
CUR_XMIN    = 8
CUR_XMAX    = 247

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
  STA HISCORE
  STA HISCORE+1
  STA HISCORE+2
  STA FRAME_CNT
  STA LAST_FRAME
  STA SND_THR
  LDA #$A5
  STA RND
  JSR HIDE_SPRITES
  JMP TITLE


; ===============================================================
;  TITLE SCREEN
; ===============================================================
TITLE:
  LDX #$FF
  TXS                          ; no way back from here: clean stack
  JSR HIDE_SPRITES
  LDA #$00
  STA SND_THR
  JSR VDP_INT_OFF
  JSR CLEAR_SCREEN
  LDA #$01
  STA LEVEL
  JSR LOAD_LEVEL
  JSR DRAW_STARS
  JSR DRAW_TERRAIN
  JSR DRAW_PAD_LABELS
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
  LDA #$F1
  STA TCOL
  LDA #1
  STA CELLR
  LDA #17
  STA CELLC
  LDA HISCORE+2
  JSR PUT_BCD
  LDA HISCORE+1
  JSR PUT_BCD
  LDA HISCORE
  JSR PUT_BCD
  LDA #232                     ; decoration: lander with its engine on
  STA POSXH
  LDA #104
  STA POSYH
  LDA #$00
  STA ANG
  STA STATE
  LDA #$01
  STA THR
  JSR BUILD_SAT
  JSR VDP_INT_ON
  LDA #CMD_TITLE               ; short intro tune (a button skips it)
  STA SND_CMD
  JSR WAIT_FIRE
  LDA FRAME_CNT                ; the moment you press seeds the random generator
  ORA #$01
  STA RND
  JMP NEW_GAME


; ===============================================================
;  NEW GAME
; ===============================================================
NEW_GAME:
  LDA #CMD_GAME                ; stop the tune, game effects
  STA SND_CMD
  LDA #$00
  STA SCORE
  STA SCORE+1
  STA SCORE+2
  STA SND_THR
  STA THR
  LDA #$01
  STA LEVEL
  LDA #$03
  STA LIVES
  JSR HIDE_SPRITES
  JSR VDP_INT_OFF
  JSR CLEAR_SCREEN
  LDA #<TXT_HUD
  STA TP
  LDA #>TXT_HUD
  STA TP+1
  JSR DRAW_TEXT
  JMP LEVEL_START


; ===============================================================
;  START OF A LEVEL
; ===============================================================
LEVEL_START:
  LDX #$FF
  TXS
  JSR HIDE_SPRITES
  LDA #$00
  STA SND_THR
  STA THR
  LDA #CMD_GAME
  STA SND_CMD
  JSR VDP_INT_OFF
  LDA #2
  LDX #22
  JSR CLEAR_ROWS               ; rows 2-23 (rows 0-1 = HUD)
  JSR LOAD_LEVEL
  JSR DRAW_STARS
  JSR DRAW_TERRAIN
  JSR DRAW_PAD_LABELS
  JSR INIT_LANDER
  JSR DRAW_STATUS
  LDA #$02
  STA HUDT
  JSR UPDATE_HUD
  JSR BUILD_SAT
  LDA #<TXT_LEVEL
  STA TP
  LDA #>TXT_LEVEL
  STA TP+1
  JSR DRAW_TEXT
  LDA #$B1
  STA TCOL
  LDA #5
  STA CELLR
  LDA #18
  STA CELLC
  LDA LEVEL
  JSR BIN2BCD
  JSR PUT_BCD
  JSR VDP_INT_ON
  JSR WAIT_FRAME
  JSR WAIT_FRAME
  LDA #W_START
  LDX #2
  JSR SFX_WHISTLE
  LDA #100
  JSR WAIT_FRAMES
  JSR VDP_INT_OFF              ; erase the message
  LDA #<TXT_BLANK1
  STA TP
  LDA #>TXT_BLANK1
  STA TP+1
  JSR DRAW_TEXT
  JSR VDP_INT_ON


; ===============================================================
;  GAME LOOP: one pass = one frame
; ===============================================================
GAME_LOOP:
  JSR VDP_INT_OFF              ; waits for the vblank and frees the VDP
  JSR READ_JOY
  JSR NEXT_RND
  JSR UPDATE_LANDER
  JSR UPDATE_HUD
  JSR BUILD_SAT
  JSR VDP_INT_ON
  LDA STATE
  BNE .gl_end
  JMP GAME_LOOP
.gl_end:
  JMP LEVEL_END


; ---------------------------------------------------------------
; end of the attempt: landed (1) or crashed (2)
; ---------------------------------------------------------------
LEVEL_END:
  LDX #$FF
  TXS
  LDA #$00
  STA SND_THR                  ; engine roar off
  LDA STATE
  CMP #$01
  BEQ LANDED
  JMP CRASH

LANDED:
  LDA #S_THUD                  ; touchdown thud + chirp
  LDX #2
  JSR SFX_BOOM
  LDA #W_LAND
  LDX #2
  JSR SFX_WHISTLE
  LDA #22
  JSR WAIT_FRAMES
  ; score = pad points x multiplier + (fuel / 16)
  LDX MULT
  LDA PTS_LO,X
  STA ADLO
  LDA PTS_MID,X
  STA ADMID
  LDA FUELL
  LSR A
  LSR A
  LSR A
  LSR A
  STA T0
  LDA FUELH
  ASL A
  ASL A
  ASL A
  ASL A
  ORA T0
  CMP #100
  BCC .la_f
  LDA #99
.la_f:
  JSR BIN2BCD
  SED
  CLC
  ADC ADLO
  STA ADLO
  LDA ADMID
  ADC #$00
  STA ADMID
  CLD
  JSR ADD_SCORE
  JSR VDP_INT_OFF
  LDA #<TXT_LAND
  STA TP
  LDA #>TXT_LAND
  STA TP+1
  JSR DRAW_TEXT
  LDA #$B1
  STA TCOL
  LDA #6
  STA CELLR
  LDA #17
  STA CELLC
  LDA MULT
  ORA #$30
  JSR PUT_CHAR
  LDA #8
  STA CELLR
  LDA #17
  STA CELLC
  LDA ADMID
  JSR PUT_BCD
  LDA ADLO
  JSR PUT_BCD
  JSR DRAW_STATUS
  JSR VDP_INT_ON
  LDA #CMD_WIN                 ; victory fanfare
  JSR PLAY_SONG
  JSR WAIT_SONG
  INC LEVEL
  JMP LEVEL_START

CRASH:
  LDA #S_BIG                   ; explosion
  LDX #2
  JSR SFX_BOOM
  LDA #$00
  STA EXT
.cr_l:
  JSR WAIT_FRAME
  LDA EXT
  LSR A
  LSR A
  LSR A
  CMP #4
  BCC .cr_f
  LDA #3
.cr_f:
  STA EXF
  JSR BUILD_SAT
  INC EXT
  LDA EXT
  CMP #64
  BNE .cr_l
  JSR HIDE_SPRITES
  JSR VDP_INT_OFF
  LDA #<TXT_CRASH
  STA TP
  LDA #>TXT_CRASH
  STA TP+1
  JSR DRAW_TEXT
  LDX REASON
  LDA REASON_TL,X
  STA TP
  LDA REASON_TH,X
  STA TP+1
  JSR DRAW_TEXT
  JSR VDP_INT_ON
  LDA #CMD_CRASH               ; defeat sting
  JSR PLAY_SONG
  JSR WAIT_SONG
  DEC LIVES
  BEQ .cr_over
  JMP LEVEL_START
.cr_over:
  JMP GAME_OVER


; ===============================================================
;  GAME OVER
; ===============================================================
GAME_OVER:
  LDX #$FF
  TXS
  JSR HIDE_SPRITES
  LDA #$00
  STA SND_THR
  LDA SCORE+2                  ; hi score
  CMP HISCORE+2
  BCC .go_nr
  BNE .go_new
  LDA SCORE+1
  CMP HISCORE+1
  BCC .go_nr
  BNE .go_new
  LDA SCORE
  CMP HISCORE
  BCC .go_nr
  BEQ .go_nr
.go_new:
  LDA SCORE
  STA HISCORE
  LDA SCORE+1
  STA HISCORE+1
  LDA SCORE+2
  STA HISCORE+2
.go_nr:
  JSR VDP_INT_OFF
  LDA #1
  LDX #23
  JSR CLEAR_ROWS               ; keeps only the score row
  JSR DRAW_STARS
  LDA #<OVER_BIG
  STA TP
  LDA #>OVER_BIG
  STA TP+1
  JSR DRAW_BIGWORDS
  LDA #<TXT_OVER
  STA TP
  LDA #>TXT_OVER
  STA TP+1
  JSR DRAW_TEXT
  LDA #$F1
  STA TCOL
  LDA #11
  STA CELLR
  LDA #17
  STA CELLC
  LDA SCORE+2
  JSR PUT_BCD
  LDA SCORE+1
  JSR PUT_BCD
  LDA SCORE
  JSR PUT_BCD
  LDA #13
  STA CELLR
  LDA #17
  STA CELLC
  LDA HISCORE+2
  JSR PUT_BCD
  LDA HISCORE+1
  JSR PUT_BCD
  LDA HISCORE
  JSR PUT_BCD
  JSR DRAW_STATUS
  JSR VDP_INT_ON
  LDA #CMD_LOSE                ; final music
  JSR PLAY_SONG
  JSR WAIT_SONG
  JSR VDP_INT_OFF
  LDA #<TXT_PRESS
  STA TP
  LDA #>TXT_PRESS
  STA TP+1
  JSR DRAW_TEXT
  JSR VDP_INT_ON
  JSR WAIT_FIRE
  JMP TITLE


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

PLAY_SONG:                     ; A = CMD_*; returns when the NMI has started it
  STA SND_CMD
  JSR WAIT_FRAME
  JSR WAIT_FRAME
  RTS

WAIT_SONG:                     ; waits for the end of the song
  JSR WAIT_FRAME
  LDA SND_BUSY
  BNE WAIT_SONG
  RTS


; ===============================================================
;  LEVEL DATA: terrain, pads, fuel, gravity
; ===============================================================
LOAD_LEVEL:
  LDA LEVEL
  SEC
  SBC #1
.ll_m:
  CMP #6
  BCC .ll_d
  SBC #6
  BRA .ll_m
.ll_d:
  TAX
  STX LVI
  LDA LV_TL,X
  STA PTR
  LDA LV_TH,X
  STA PTR+1
  LDY #$00
.ll_c:
  LDA (PTR),Y
  STA TERR,Y
  INY
  BNE .ll_c
  LDA #$00
.ll_z:
  STA PADM,Y
  INY
  BNE .ll_z
  LDX LVI
  LDA LV_PL,X
  STA PPL
  LDA LV_PH,X
  STA PPL+1
  LDY #$00
.ll_p:
  LDA (PPL),Y
  CMP #$FF
  BEQ .ll_pe
  STA T6                       ; first x
  INY
  LDA (PPL),Y
  STA T7                       ; last x
  INY
  LDA (PPL),Y
  STA T2                       ; multiplier
  LDX T6
.ll_f:
  LDA T2
  STA PADM,X
  CPX T7
  BEQ .ll_fe
  INX
  BRA .ll_f
.ll_fe:
  INY
  BRA .ll_p
.ll_pe:
  LDA LEVEL                    ; difficulty (max index 7)
  SEC
  SBC #1
  CMP #8
  BCC .ll_dd
  LDA #7
.ll_dd:
  TAX
  LDA GRAV_TAB,X
  STA GRAV
  LDA FUEL_LO,X
  STA FUELL
  LDA FUEL_HI,X
  STA FUELH
  RTS

INIT_LANDER:
  LDX LVI
  LDA LV_SX,X
  STA POSXH
  LDA #$00
  STA POSXL
  STA POSYL
  STA VYL
  STA VYH
  STA ANG
  STA THR
  STA STATE
  STA ROTT
  STA LOWT
  STA ALMT
  STA REASON
  STA EXF
  LDA #30
  STA POSYH
  LDA LV_SVX,X
  STA VXL
  BMI .il_n
  LDA #$00
  BRA .il_s
.il_n:
  LDA #$FF
.il_s:
  STA VXH
  RTS


; ===============================================================
;  LANDER: controls, physics, sounds, contact
; ===============================================================
UPDATE_LANDER:
  LDA P_JOY
  ORA P_JOY+1
  STA JOYC
  ; ---- rotation
  LDA ROTT
  BEQ .ul_rot
  DEC ROTT
  BRA .ul_thr
.ul_rot:
  LDA JOYC
  AND #%00000100               ; left
  BEQ .ul_nl
  LDA ANG
  SEC
  SBC #1
  AND #$0F
  STA ANG
  LDA #ROT_DELAY
  STA ROTT
  LDA #W_ROT
  LDX #0                       ; tick on the left speaker
  JSR SFX_WHISTLE
  BRA .ul_thr
.ul_nl:
  LDA JOYC
  AND #%00001000               ; right
  BEQ .ul_thr
  LDA ANG
  CLC
  ADC #1
  AND #$0F
  STA ANG
  LDA #ROT_DELAY
  STA ROTT
  LDA #W_ROT
  LDX #1                       ; tick on the right speaker
  JSR SFX_WHISTLE
.ul_thr:
  ; ---- engine
  LDA #$00
  STA THR
  STA SND_THR
  LDA JOYC
  AND #%00110001               ; up or buttons
  BEQ .ul_grav
  LDA FUELL
  ORA FUELH
  BEQ .ul_grav                 ; out of fuel
  LDA FUELL
  SEC
  SBC #1
  STA FUELL
  LDA FUELH
  SBC #0
  STA FUELH
  LDA #$01
  STA THR
  STA SND_THR
  LDY ANG
  LDA THX,Y
  LDX #0
  JSR ADD_SIGNED
  LDY ANG
  LDA THY,Y
  LDX #2
  JSR ADD_SIGNED
  LDA FUELL
  ORA FUELH
  BNE .ul_grav
  LDA #W_NOFUEL                ; the tank has just run dry
  LDX #2
  JSR SFX_WHISTLE
.ul_grav:
  LDA GRAV
  LDX #2
  JSR ADD_SIGNED
  ; ---- position
  CLC
  LDA POSXL
  ADC VXL
  STA POSXL
  LDA POSXH
  ADC VXH
  STA POSXH
  CLC
  LDA POSYL
  ADC VYL
  STA POSYL
  LDA POSYH
  ADC VYH
  STA POSYH
  LDA POSXH                    ; side walls
  CMP #CUR_XMIN
  BCC .ul_wl
  CMP #(CUR_XMAX+1)
  BCC .ul_wok
  LDA #CUR_XMAX
  BRA .ul_ws
.ul_wl:
  LDA #CUR_XMIN
.ul_ws:
  STA POSXH
  LDA #$00
  STA POSXL
  STA VXL
  STA VXH
.ul_wok:
  LDA POSYH                    ; ceiling
  CMP #20
  BCS .ul_cok
  LDA VYH
  BPL .ul_cok
  LDA #20
  STA POSYH
  LDA #$00
  STA POSYL
  STA VYL
  STA VYH
.ul_cok:
  ; ---- warnings
  LDA FUELH
  BNE .ul_nolow
  LDA FUELL
  BEQ .ul_nolow
  CMP #200
  BCS .ul_nolow
  LDA LOWT
  BEQ .ul_low
  DEC LOWT
  BRA .ul_nolow
.ul_low:
  LDA #W_LOW                   ; low fuel: beep
  LDX #2
  JSR SFX_WHISTLE
  LDA #26
  STA LOWT
.ul_nolow:
  LDA ALMT
  BEQ .ul_alm
  DEC ALMT
  BRA .ul_cont
.ul_alm:
  LDA VYH
  BMI .ul_cont                 ; going up
  LDX #2
  JSR ABS_VEL
  CMP #(VY_MAX+1)
  BCC .ul_cont
  JSR CALC_ALT
  CMP #44
  BCS .ul_cont
  LDA #W_ALARM                 ; too fast and close to the ground
  LDX #2
  JSR SFX_WHISTLE
  LDA #20
  STA ALMT
.ul_cont:
  ; ---- contact with the ground: feet at (x-6, x, x+6), bottom = y+8
  LDA POSYH
  CLC
  ADC #8
  STA T2
  LDA POSXH
  SEC
  SBC #6
  TAX
  LDA T2
  CMP TERR,X
  BCS .ul_touch
  LDX POSXH
  LDA T2
  CMP TERR,X
  BCS .ul_touch
  LDA POSXH
  CLC
  ADC #6
  TAX
  LDA T2
  CMP TERR,X
  BCS .ul_touch
  RTS
.ul_touch:
  ; ---- evaluate: rocks? too fast? bad angle?
  LDA POSXH
  SEC
  SBC #6
  TAX
  LDA PADM,X
  BEQ .ul_rocks
  STA MULT
  LDA POSXH
  CLC
  ADC #6
  TAX
  LDA PADM,X
  CMP MULT
  BNE .ul_rocks
  LDX POSXH
  LDA PADM,X
  CMP MULT
  BNE .ul_rocks
  LDX #2
  JSR ABS_VEL
  CMP #(VY_MAX+1)
  BCS .ul_fast
  LDX #0
  JSR ABS_VEL
  CMP #(VX_MAX+1)
  BCS .ul_fast
  LDA ANG
  CLC
  ADC #1
  AND #$0F
  CMP #3
  BCS .ul_angle
  LDX POSXH                    ; perfect: snap the feet onto the pad
  LDA TERR,X
  SEC
  SBC #8
  STA POSYH
  LDA #$00
  STA POSYL
  STA VXL
  STA VXH
  STA VYL
  STA VYH
  STA THR
  LDA #$01
  STA STATE
  RTS
.ul_rocks:
  LDA #3
  BRA .ul_crash
.ul_fast:
  LDA #1
  BRA .ul_crash
.ul_angle:
  LDA #2
.ul_crash:
  STA REASON
  LDA #$02
  STA STATE
  LDA #$00
  STA THR
  RTS

; VEL[X..X+1] += A (signed 8 bit).  X = 0 (vx) or 2 (vy)
ADD_SIGNED:
  STA T1
  CLC
  ADC VXL,X
  STA VXL,X
  LDA T1
  BPL .as_p
  LDA #$FF
  BRA .as_h
.as_p:
  LDA #$00
.as_h:
  ADC VXH,X
  STA VXH,X
  RTS

; A = |velocity| (1/256 px per frame, max 255).  X = 0 (vx) or 2 (vy)
ABS_VEL:
  LDA VXH,X
  BPL .av_pos
  LDA #$00
  SEC
  SBC VXL,X
  STA T6
  LDA #$00
  SBC VXH,X
  BNE .av_big
  LDA T6
  RTS
.av_pos:
  BNE .av_big
  LDA VXL,X
  RTS
.av_big:
  LDA #$FF
  RTS

; A = altitude of the feet over the surface under the lander (0 if below)
CALC_ALT:
  LDX POSXH
  LDA TERR,X
  SEC
  SBC POSYH
  BCC .ca_0
  SEC
  SBC #8
  BCS .ca_r
.ca_0:
  LDA #$00
.ca_r:
  RTS


; ===============================================================
;  HUD
; ===============================================================
; score, hi score, level, lives (rows 0)
DRAW_STATUS:
  LDA #$F1
  STA TCOL
  LDA #0
  STA CELLR
  LDA #6
  STA CELLC
  LDA SCORE+2
  JSR PUT_BCD
  LDA SCORE+1
  JSR PUT_BCD
  LDA SCORE
  JSR PUT_BCD
  LDA #16
  STA CELLC
  LDA HISCORE+2
  JSR PUT_BCD
  LDA HISCORE+1
  JSR PUT_BCD
  LDA HISCORE
  JSR PUT_BCD
  LDA #$B1
  STA TCOL
  LDA #26
  STA CELLC
  LDA LEVEL
  JSR BIN2BCD
  JSR PUT_BCD
  LDA #31
  STA CELLC
  LDA LIVES
  ORA #$30
  JMP PUT_CHAR

; fuel, altitude and speeds (row 1), every 3 frames
UPDATE_HUD:
  INC HUDT
  LDA HUDT
  CMP #3
  BCC .uh_ret
  LDA #$00
  STA HUDT
  LDA #1
  STA CELLR
  ; fuel
  LDA #5
  STA CELLC
  LDA #$F1
  LDX FUELH
  BNE .uh_fc
  LDX FUELL
  CPX #200
  BCS .uh_fc
  LDA #$91                     ; low: red
.uh_fc:
  STA TCOL
  JSR FUEL_DIGITS
  ; altitude
  LDA #14
  STA CELLC
  LDA #$F1
  STA TCOL
  JSR CALC_ALT
  JSR PRINT3
  ; horizontal speed
  LDA #20
  STA CELLC
  LDX #0
  JSR SPEED_PRINT
  ; vertical speed
  LDA #27
  STA CELLC
  LDX #2
  JSR SPEED_PRINT
.uh_ret:
  RTS

; X = 0 (vx) / 2 (vy): sign + 2 digits at (CELLC,CELLR); green = safe, red = too fast
SPEED_PRINT:
  STX T7
  JSR ABS_VEL
  STA T6
  LDX T7
  LDA #$31                     ; green
  CPX #2
  BEQ .sp_y
  LDY T6
  CPY #(VX_MAX+1)
  BRA .sp_c
.sp_y:
  LDY T6
  CPY #(VY_MAX+1)
.sp_c:
  BCC .sp_ok
  LDA #$91                     ; red
.sp_ok:
  STA TCOL
  LDX T7
  LDA VXH,X                    ; sign: vx + = right; vy shown - = descending
  BMI .sp_neg
  CPX #2
  BEQ .sp_m
  LDA #$2B
  BRA .sp_ch
.sp_neg:
  CPX #2
  BEQ .sp_p
  LDA #$2D
  BRA .sp_ch
.sp_m:
  LDA #$2D
  BRA .sp_ch
.sp_p:
  LDA #$2B
.sp_ch:
  JSR PUT_CHAR
  INC CELLC
  LDA T6
  LSR A
  LSR A
  LSR A
  CMP #100
  BCC .sp_v
  LDA #99
.sp_v:
  JSR BIN2BCD
  JMP PUT_BCD

PRINT3:                        ; A = 0-255 -> three digits
  LDX #$30
.p3h:
  CMP #100
  BCC .p3t
  SBC #100
  INX
  BRA .p3h
.p3t:
  PHA
  TXA
  JSR PUT_CHAR
  INC CELLC
  PLA
  JSR BIN2BCD
  JMP PUT_BCD

FUEL_DIGITS:                   ; fuel as 4 decimal digits
  LDA FUELL
  STA T2
  LDA FUELH
  STA T3
  LDX #$00
.fd_d:
  LDY #$00
.fd_s:
  LDA T2
  SEC
  SBC DEC_L,X
  STA T6
  LDA T3
  SBC DEC_H,X
  BCC .fd_done
  STA T3
  LDA T6
  STA T2
  INY
  BRA .fd_s
.fd_done:
  TYA
  ORA #$30
  JSR PUT_CHAR
  INC CELLC
  INX
  CPX #3
  BNE .fd_d
  LDA T2
  ORA #$30
  JMP PUT_CHAR

ADD_SCORE:
  SED
  CLC
  LDA SCORE
  ADC ADLO
  STA SCORE
  LDA SCORE+1
  ADC ADMID
  STA SCORE+1
  LDA SCORE+2
  ADC #$00
  STA SCORE+2
  CLD
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


; ===============================================================
;  TERRAIN, STARS, PAD LABELS  (drawn once per level, VDP free)
; ===============================================================
DRAW_TERRAIN:                  ; outline of the surface, pads are 2 pixels thick
  LDX #$00
.dt_x:
  STX PX
  LDA TERR,X
  STA T6
  LDA TERR+1,X
  STA T7
  LDY PADM,X
  STY T4                       ; pad flag
  LDA PADCOL,Y
  STA PCOL
  LDA T6
  CMP T7
  BCC .dt_lo
  LDA T7
  LDY T6
  STY T7
.dt_lo:
  STA PY
.dt_y:
  JSR PLOT_SET
  LDA T4
  BEQ .dt_nt
  INC PY
  JSR PLOT_SET
  DEC PY
.dt_nt:
  INC PY
  LDA PY
  CMP T7
  BCC .dt_y
  BEQ .dt_y
  INX
  CPX #255
  BNE .dt_x
  RTS

DRAW_STARS:
  LDA #52
  STA T7
.st_l:
  JSR NEXT_RND
  LDA RND
  STA PX
  JSR NEXT_RND
  JSR NEXT_RND
  LDA RND
  AND #$7F
  CLC
  ADC #20
  STA PY
  LDX PX
  LDA TERR,X
  SEC
  SBC #14
  CMP PY
  BCC .st_n
  BEQ .st_n
  LDA RND
  AND #$03
  TAX
  LDA STARCOL,X
  STA PCOL
  JSR PLOT_SET
.st_n:
  DEC T7
  BNE .st_l
  RTS

DRAW_PAD_LABELS:               ; "X2".."X5" under every pad
  LDA #$00
  STA PADI
.pl_n:
  LDY PADI
  LDA (PPL),Y
  CMP #$FF
  BEQ .pl_end
  LSR A
  STA T6
  INY
  LDA (PPL),Y
  LSR A
  CLC
  ADC T6
  LSR A
  LSR A
  LSR A
  SEC
  SBC #1
  STA CELLC
  LDY PADI
  LDA (PPL),Y
  TAX
  LDA TERR,X
  CLC
  ADC #1
  LSR A
  LSR A
  LSR A
  CLC
  ADC #1
  STA CELLR
  LDY PADI
  INY
  INY
  LDA (PPL),Y
  STA T7
  TAX
  LDA PADCOL,X
  STA TCOL
  LDA #$58
  JSR PUT_CHAR
  INC CELLC
  LDA T7
  ORA #$30
  JSR PUT_CHAR
  LDA PADI
  CLC
  ADC #3
  STA PADI
  BRA .pl_n
.pl_end:
  RTS


; ===============================================================
;  SPRITES (lander, flame, explosion) and NMI
; ===============================================================
BUILD_SAT:
  LDA STATE
  CMP #$02
  BEQ .bs_ex
  JMP .bs_fly
.bs_ex:
  ; ---- explosion: 4 sprites 16x16 = 32x32, centred on the lander
  LDA #HIDE_Y
  STA SAT_BUFFER
  STA SAT_BUFFER+4
  LDA POSXH
  SEC
  SBC #16
  BCS .bs_x1
  LDA #$00
.bs_x1:
  STA T6                       ; left column X
  LDA POSXH
  STA T7                       ; right column X
  LDA POSYH
  SEC
  SBC #17
  STA T4                       ; top row Y
  CLC
  ADC #16
  STA T5                       ; bottom row Y
  LDA EXF
  ASL A
  ASL A
  ASL A
  ASL A
  CLC
  ADC #128
  STA T3                       ; first pattern of the frame
  LDA FRAME_CNT
  AND #$02
  BEQ .bs_c1
  LDA #$0A
  BRA .bs_c2
.bs_c1:
  LDA #$09
.bs_c2:
  STA T2
  LDA T4
  STA SAT_BUFFER+8
  LDA T6
  STA SAT_BUFFER+9
  LDA T3
  CLC
  ADC #0
  STA SAT_BUFFER+10
  LDA T2
  STA SAT_BUFFER+11
  LDA T4
  STA SAT_BUFFER+12
  LDA T7
  STA SAT_BUFFER+13
  LDA T3
  CLC
  ADC #4
  STA SAT_BUFFER+14
  LDA T2
  STA SAT_BUFFER+15
  LDA T5
  STA SAT_BUFFER+16
  LDA T6
  STA SAT_BUFFER+17
  LDA T3
  CLC
  ADC #8
  STA SAT_BUFFER+18
  LDA T2
  STA SAT_BUFFER+19
  LDA T5
  STA SAT_BUFFER+20
  LDA T7
  STA SAT_BUFFER+21
  LDA T3
  CLC
  ADC #12
  STA SAT_BUFFER+22
  LDA T2
  STA SAT_BUFFER+23
  RTS
.bs_fly:
  ; ---- lander body (sprite 0)
  LDA POSYH
  SEC
  SBC #9
  STA SAT_BUFFER
  LDA POSXH
  SEC
  SBC #8
  STA SAT_BUFFER+1
  LDA ANG
  ASL A
  ASL A
  STA SAT_BUFFER+2
  LDA #$0F
  STA SAT_BUFFER+3
  ; ---- flame (sprite 1)
  LDA THR
  BEQ .bs_nof
  LDX ANG
  LDA POSYH
  CLC
  ADC FOY,X
  SEC
  SBC #9
  STA SAT_BUFFER+4
  LDA POSXH
  CLC
  ADC FOX,X
  SEC
  SBC #8
  STA SAT_BUFFER+5
  TXA
  ASL A
  ASL A
  CLC
  ADC #64
  STA SAT_BUFFER+6
  LDA FRAME_CNT
  AND #$02
  BEQ .bs_f1
  LDA #$0A
  BRA .bs_f2
.bs_f1:
  LDA #$09
.bs_f2:
  STA SAT_BUFFER+7
  BRA .bs_hx
.bs_nof:
  LDA #HIDE_Y
  STA SAT_BUFFER+4
.bs_hx:
  LDA #HIDE_Y                  ; explosion sprites hidden
  STA SAT_BUFFER+8
  STA SAT_BUFFER+12
  STA SAT_BUFFER+16
  STA SAT_BUFFER+20
  RTS

HIDE_SPRITES:
  LDA #HIDE_Y
  STA SAT_BUFFER
  STA SAT_BUFFER+4
  STA SAT_BUFFER+8
  STA SAT_BUFFER+12
  STA SAT_BUFFER+16
  STA SAT_BUFFER+20
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
  CPX #25                 ; 6 sprites x 4 bytes + Y=$D0 of the 7th entry
  BNE .copy_sat
  JSR SND_TICK            ; music and sound effects
  RTS                     ; the BIOS NMI_HANDLER rereads VREG and does RTI

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
SAT_BUFFER:    .byte HIDE_Y,$00,$00,$0F
               .byte HIDE_Y,$00,$00,$09
               .byte HIDE_Y,$00,$00,$09
               .byte HIDE_Y,$00,$00,$09
               .byte HIDE_Y,$00,$00,$09
               .byte HIDE_Y,$00,$00,$09
               .byte $D0


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



; first row in A, number of rows in X: clears patterns and colours (black on black)
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
  LDA #$11
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
  LDA #$11
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


LOAD_SPRITES:                  ; sprite patterns at $1800 (6 pages = 1536 bytes)
  LDA #$00
  STA VREG
  LDA #(VDP_WRITE_VRAM_BIT | $18)
  STA VREG
  LDA #<SPRITES
  STA PTR
  LDA #>SPRITES
  STA PTR+1
  LDX #$06
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
; called by the NMI: A,X,Y saved here
; ---------------------------------------------------------------
SND_TICK:
  PHA
  PHX
  PHY
  INC SND_PH
  LDA SND_CMD
  BEQ .st_run
  LDX #$00
  STX SND_CMD
  CMP #CMD_GAME
  BNE .st_song
  JSR SND_GAME_MODE
  BRA .st_run
.st_song:
  SEC
  SBC #CMD_TITLE                ; 0 = title, 1 = game over
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
; starts a song: A = 0 title, 1 game over
; ---------------------------------------------------------------
SND_START:
  ASL A
  ASL A
  STA SN0                       ; song * 4
  JSR SND_CLEAR_SH
  LDA #$38                      ; left: 3 tones
  STA SH_L+7
  LDA #$2A                      ; right: tone A, noise B (drums), tone C
  STA SH_R+7
  LDX #$03
.ss_trk:
  TXA
  CLC
  ADC SN0
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
  LDX #$02                      ; tone tracks: 0 melody, 1 arpeggio, 2 bass
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
  ;      vibrato on long notes that are not too high
  LDX TR_NOTE
  BEQ .mt_l_off
  LDA TP_LO,X
  STA SN1
  CMP #100
  BCC .mt_l_nv
  LDA TR_AGE
  CMP #14
  BCC .mt_l_nv
  LSR A
  AND #$07
  TAY
  LDA SN1
  CLC
  ADC VIB_TAB,Y
  STA SN1
.mt_l_nv:
  LDA SN1
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
  ; ---- arpeggio: left chip only, channel B
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
  ; ---- song over?
  LDA TR_ACT
  ORA TR_ACT+1
  ORA TR_ACT+2
  ORA TR_ACT+3
  BNE .mt_end
  JSR SND_GAME_MODE             ; silence, SND_BUSY = 0
.mt_end:
  RTS

; ---------------------------------------------------------------
; game effects (one frame, called by the NMI). Chip 0 = left, 1 = right.
;   tone effect: id in WH_ID, tables WH_*  (channel A)
;   explosion: id in EX_ID, tables EX_*  (noise B + thump C)
;   engine: SND_THR = 1  (noise B + rumble C, when no explosion is playing)
; ---------------------------------------------------------------
SFX_TICK:
  LDA SND_RND                   ; LFSR for the crackle of the explosion
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
  LDA WH_ID,X                   ; ---- whistle
  BEQ .sf_nowh
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
  BRA .sf_nowh
.sf_whend:
  LDA #$00
  STA WH_ID,X
.sf_nowh:
  LDX SND_T1                    ; ---- explosion
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
  CPY #$00
  BEQ .sf_e2
  CLC
  ADC #$03                      ; right chip: slightly different noise
.sf_e2:
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
  BRA .sf_next
.sf_thr:
  LDA SND_THR
  BEQ .sf_next
  LDA SND_RND
  AND #$03
  CLC
  ADC #$0A
  STA SH_L+6,Y                  ; engine: noise period 10-13
  LDA #$0C
  STA SH_L+9,Y                  ; noise volume
  LDA SND_RND
  AND #$3F
  CLC
  ADC #$80
  STA SH_L+4,Y                  ; low rumble on channel C
  LDA #$02
  STA SH_L+5,Y
  LDA #$06
  STA SH_L+10,Y
.sf_next:
  LDX SND_T1
  DEX
  BMI .sf_done
  JMP .sf_chip
.sf_done:
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
;  TABLES (generated)
; ===============================================================
BITMASK:    .byte $80,$40,$20,$10,$08,$04,$02,$01
PADCOL:     .byte $E1,$31,$31,$B1,$91,$D1      ; surface colour: rock, pads x2 x3 x4 x5
STARCOL:    .byte $F1,$E1,$F1,$51
PTS_LO:     .byte $00,$50,$00,$50,$00,$50           ; points of a landing (BCD) by multiplier: 50,100,150,200,250
PTS_MID:    .byte $00,$00,$01,$01,$02,$02
DEC_L:      .byte $E8,$64,$0A                       ; 1000, 100, 10
DEC_H:      .byte $03,$00,$00
GRAV_TAB:   .byte 3,3,4,4,4,5,5,6                   ; gravity (1/256 px per frame^2) by difficulty
FUEL_LO:    .byte <1200,<1100,<1000,<950,<900,<850,<800,<750
FUEL_HI:    .byte >1200,>1100,>1000,>950,>900,>850,>800,>750
LV_SX:      .byte 40,200,30,220,128,40              ; start X of every map
LV_SVX:     .byte 60,$C4,70,$BA,60,$C4              ; start drift
THX:
  .byte $00,$05,$0A,$0D,$0E,$0D,$0A,$05,$00,$FB,$F6,$F3,$F2,$F3,$F6,$FB
THY:
  .byte $F2,$F3,$F6,$FB,$00,$05,$0A,$0D,$0E,$0D,$0A,$05,$00,$FB,$F6,$F3
FOX:
  .byte $00,$FC,$F8,$F6,$F5,$F6,$F8,$FC,$00,$04,$08,$0A,$0B,$0A,$08,$04
FOY:
  .byte $0B,$0A,$08,$04,$00,$FC,$F8,$F6,$F5,$F6,$F8,$FC,$00,$04,$08,$0A
LV_TL:      .byte <TERR0,<TERR1,<TERR2,<TERR3,<TERR4,<TERR5
LV_TH:      .byte >TERR0,>TERR1,>TERR2,>TERR3,>TERR4,>TERR5
LV_PL:      .byte <PADS0,<PADS1,<PADS2,<PADS3,<PADS4,<PADS5
LV_PH:      .byte >PADS0,>PADS1,>PADS2,>PADS3,>PADS4,>PADS5
REASON_TL:  .byte <TXT_R0,<TXT_R1,<TXT_R2,<TXT_R3
REASON_TH:  .byte >TXT_R0,>TXT_R1,>TXT_R2,>TXT_R3
TERR0:
  .byte $96,$96,$95,$95,$95,$94,$94,$94,$93,$93,$93,$92,$92,$92,$91,$91
  .byte $91,$90,$90,$90,$8F,$8F,$8F,$8E,$8E,$8E,$8D,$8D,$8D,$8C,$8C,$8C
  .byte $8B,$8B,$8B,$8A,$8A,$8B,$8C,$8C,$8D,$8E,$8F,$90,$90,$91,$92,$93
  .byte $93,$94,$95,$96,$97,$97,$98,$99,$9A,$9A,$9B,$9C,$9D,$9E,$9E,$9F
  .byte $A0,$A0,$A1,$A1,$A1,$A2,$A2,$A2,$A3,$A3,$A3,$A4,$A4,$A4,$A5,$A5
  .byte $A5,$A6,$A6,$A6,$A7,$A7,$A7,$A8,$A8,$A8,$A9,$A9,$A9,$AA,$AA,$AA
  .byte $AB,$AB,$AB,$AC,$AC,$AC,$AC,$AC,$AC,$AC,$AC,$AC,$AC,$AC,$AC,$AC
  .byte $AC,$AC,$AC,$AC,$AC,$AC,$AC,$AC,$AC,$AC,$AC,$AC,$AC,$AC,$AC,$AC
  .byte $AC,$AC,$AC,$AC,$AC,$AC,$AC,$AC,$AC,$AB,$AA,$A9,$A8,$A7,$A6,$A6
  .byte $A5,$A4,$A3,$A2,$A1,$A0,$9F,$9E,$9D,$9C,$9C,$9B,$9A,$99,$98,$97
  .byte $96,$96,$97,$97,$97,$97,$98,$98,$98,$98,$99,$99,$99,$99,$9A,$9A
  .byte $9A,$9B,$9B,$9B,$9B,$9C,$9C,$9C,$9C,$9D,$9D,$9D,$9D,$9E,$9E,$9E
  .byte $9F,$9F,$A0,$A0,$A0,$A1,$A1,$A2,$A2,$A3,$A3,$A3,$A4,$A4,$A5,$A5
  .byte $A6,$A6,$A6,$A7,$A7,$A8,$A8,$A8,$A8,$A8,$A8,$A8,$A8,$A8,$A8,$A8
  .byte $A8,$A8,$A8,$A8,$A8,$A8,$A8,$A8,$A8,$A8,$A8,$A8,$A8,$A8,$A8,$A8
  .byte $A8,$A8,$A8,$A8,$A8,$A6,$A5,$A3,$A1,$A0,$9E,$9D,$9B,$99,$98,$96
TERR1:
  .byte $6E,$6D,$6C,$6C,$6B,$6A,$69,$68,$67,$67,$66,$65,$64,$63,$63,$62
  .byte $61,$60,$5F,$5E,$5E,$5D,$5C,$5E,$5F,$61,$63,$64,$66,$67,$69,$6B
  .byte $6C,$6E,$70,$71,$73,$75,$76,$78,$79,$7B,$7D,$7E,$80,$81,$82,$83
  .byte $83,$84,$85,$86,$87,$88,$88,$89,$8A,$8B,$8C,$8D,$8E,$8E,$8F,$90
  .byte $91,$92,$93,$93,$94,$95,$96,$96,$96,$96,$96,$96,$96,$96,$96,$96
  .byte $96,$96,$96,$96,$96,$96,$96,$96,$96,$96,$96,$96,$96,$96,$96,$96
  .byte $96,$96,$96,$95,$93,$92,$91,$8F,$8E,$8C,$8B,$8A,$88,$87,$86,$84
  .byte $83,$82,$80,$7F,$7D,$7C,$7B,$79,$78,$76,$74,$72,$70,$6E,$6C,$6A
  .byte $68,$66,$64,$62,$60,$5E,$5C,$5A,$58,$56,$54,$56,$57,$59,$5A,$5C
  .byte $5D,$5F,$60,$62,$63,$65,$67,$68,$6A,$6B,$6D,$6E,$70,$71,$73,$74
  .byte $76,$78,$7A,$7C,$7F,$81,$83,$85,$87,$8A,$8C,$8E,$90,$92,$94,$96
  .byte $99,$9B,$9D,$9F,$A1,$A4,$A6,$A8,$AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA
  .byte $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA
  .byte $AA,$AA,$AA,$AA,$AA,$A9,$A8,$A6,$A5,$A4,$A2,$A1,$A0,$9F,$9E,$9C
  .byte $9B,$9A,$98,$97,$96,$95,$94,$92,$91,$90,$8E,$8D,$8C,$8B,$8B,$8A
  .byte $89,$89,$88,$88,$87,$86,$86,$85,$84,$84,$83,$83,$82,$81,$81,$80
TERR2:
  .byte $82,$83,$83,$84,$85,$86,$86,$87,$88,$88,$89,$8A,$8B,$8B,$8C,$8D
  .byte $8D,$8E,$8F,$90,$90,$91,$92,$92,$93,$94,$95,$95,$96,$97,$98,$99
  .byte $9A,$9B,$9C,$9C,$9D,$9E,$9F,$A0,$A1,$A2,$A3,$A4,$A5,$A6,$A7,$A8
  .byte $A9,$AA,$AA,$AB,$AC,$AD,$AE,$AF,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0
  .byte $B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0
  .byte $B0,$B0,$B0,$AE,$AD,$AC,$AA,$A8,$A7,$A6,$A4,$A2,$A1,$A0,$9E,$9C
  .byte $9B,$9A,$98,$96,$95,$94,$92,$90,$8F,$8E,$8C,$8A,$88,$87,$85,$83
  .byte $82,$80,$7E,$7C,$7A,$79,$77,$75,$74,$72,$70,$70,$70,$70,$70,$70
  .byte $70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70
  .byte $70,$70,$70,$71,$73,$74,$76,$77,$78,$7A,$7B,$7D,$7E,$7F,$81,$82
  .byte $84,$85,$86,$88,$89,$8B,$8C,$8D,$8F,$90,$91,$92,$94,$95,$96,$97
  .byte $99,$9A,$9B,$9C,$9E,$9F,$A0,$A2,$A3,$A4,$A5,$A7,$A8,$A9,$AA,$AC
  .byte $AD,$AE,$AF,$B1,$B2,$B2,$B2,$B2,$B2,$B2,$B2,$B2,$B2,$B2,$B2,$B2
  .byte $B2,$B2,$B2,$B2,$B2,$B2,$B2,$B2,$B2,$B2,$B2,$B2,$B2,$B2,$B2,$B2
  .byte $B2,$B2,$B2,$B1,$B0,$AF,$AE,$AD,$AC,$AB,$AA,$A9,$A8,$A7,$A6,$A5
  .byte $A4,$A4,$A3,$A2,$A1,$A0,$9F,$9E,$9D,$9C,$9B,$9A,$99,$98,$97,$96
TERR3:
  .byte $64,$66,$67,$69,$6B,$6C,$6E,$70,$71,$73,$75,$76,$78,$7A,$7B,$7D
  .byte $7F,$80,$82,$80,$7E,$7C,$7A,$77,$75,$73,$71,$6F,$6D,$6B,$68,$66
  .byte $64,$62,$60,$62,$64,$66,$68,$6A,$6C,$6E,$70,$72,$74,$76,$78,$7A
  .byte $7C,$7E,$80,$82,$84,$86,$88,$8A,$8C,$8E,$8F,$90,$92,$94,$95,$96
  .byte $98,$9A,$9B,$9C,$9E,$A0,$A1,$A2,$A4,$A6,$A7,$A8,$AA,$AA,$AA,$AA
  .byte $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA
  .byte $AA,$AA,$AA,$AA,$AA,$A8,$A6,$A5,$A3,$A1,$9F,$9D,$9B,$9A,$98,$96
  .byte $94,$92,$91,$8F,$8D,$8B,$89,$87,$86,$84,$82,$81,$7F,$7E,$7C,$7B
  .byte $79,$78,$76,$75,$74,$72,$71,$6F,$6E,$6C,$6B,$69,$68,$6B,$6D,$70
  .byte $72,$75,$77,$7A,$7C,$7F,$82,$84,$87,$89,$8C,$8E,$91,$93,$96,$97
  .byte $99,$9A,$9B,$9D,$9E,$A0,$A1,$A2,$A4,$A5,$A6,$A8,$A9,$AA,$AC,$AD
  .byte $AF,$B0,$B1,$B3,$B4,$B4,$B4,$B4,$B4,$B4,$B4,$B4,$B4,$B4,$B4,$B4
  .byte $B4,$B4,$B4,$B4,$B4,$B4,$B4,$B4,$B4,$B4,$B4,$B4,$B4,$B4,$B4,$B2
  .byte $B0,$AF,$AD,$AB,$A9,$A7,$A5,$A4,$A2,$A0,$9E,$9C,$9B,$99,$97,$95
  .byte $93,$91,$90,$8E,$8C,$8B,$8A,$88,$87,$86,$84,$83,$82,$81,$80,$7E
  .byte $7D,$7C,$7A,$79,$78,$77,$76,$75,$74,$73,$73,$72,$71,$70,$6F,$6E
TERR4:
  .byte $64,$64,$63,$63,$62,$62,$62,$61,$61,$60,$60,$60,$60,$60,$60,$60
  .byte $60,$60,$60,$60,$60,$60,$60,$60,$60,$60,$60,$60,$60,$60,$60,$60
  .byte $60,$60,$60,$60,$60,$61,$63,$64,$66,$67,$68,$6A,$6B,$6D,$6E,$70
  .byte $71,$72,$74,$75,$77,$78,$7A,$7B,$7C,$7E,$7F,$81,$82,$84,$86,$88
  .byte $8A,$8C,$8E,$90,$92,$94,$96,$98,$9A,$9C,$9E,$A0,$A2,$A4,$A6,$A8
  .byte $AA,$AC,$AE,$B0,$B2,$B2,$B2,$B2,$B2,$B2,$B2,$B2,$B2,$B2,$B2,$B2
  .byte $B2,$B2,$B2,$B2,$B2,$B2,$B2,$B2,$B2,$B2,$B2,$B2,$B2,$B2,$B2,$B1
  .byte $AF,$AE,$AD,$AC,$AA,$A9,$A8,$A7,$A5,$A4,$A3,$A1,$A0,$9F,$9E,$9C
  .byte $9B,$9A,$99,$97,$96,$94,$92,$90,$8E,$8B,$89,$87,$85,$83,$81,$7F
  .byte $7D,$7B,$78,$76,$74,$72,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70
  .byte $70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$72,$73,$75
  .byte $76,$78,$7A,$7B,$7D,$7E,$80,$81,$83,$85,$86,$88,$89,$8B,$8C,$8E
  .byte $90,$91,$93,$94,$96,$97,$98,$98,$99,$9A,$9B,$9B,$9C,$9D,$9E,$9E
  .byte $9F,$A0,$A1,$A2,$A2,$A3,$A4,$A5,$A5,$A6,$A7,$A8,$A8,$A9,$AA,$A8
  .byte $A7,$A5,$A4,$A2,$A1,$9F,$9E,$9C,$9B,$99,$98,$96,$95,$93,$92,$90
  .byte $8F,$8D,$8C,$8A,$89,$87,$86,$84,$83,$81,$80,$7E,$7D,$7B,$7A,$78
TERR5:
  .byte $96,$94,$91,$8E,$8C,$8A,$87,$84,$82,$80,$7D,$7A,$78,$76,$73,$70
  .byte $6E,$71,$74,$77,$79,$7C,$7F,$82,$85,$88,$8B,$8D,$90,$93,$96,$95
  .byte $94,$93,$92,$91,$90,$8F,$8E,$8D,$8C,$8B,$8A,$89,$88,$87,$86,$85
  .byte $84,$83,$82,$81,$80,$83,$86,$89,$8C,$8E,$91,$94,$97,$9A,$9D,$A0
  .byte $A3,$A6,$A8,$AB,$AE,$B1,$B4,$B4,$B4,$B4,$B4,$B4,$B4,$B4,$B4,$B4
  .byte $B4,$B4,$B4,$B4,$B4,$B4,$B4,$B4,$B4,$B4,$B4,$B4,$B4,$B4,$B4,$B3
  .byte $B1,$B0,$AF,$AD,$AC,$AA,$A9,$A8,$A6,$A5,$A4,$A2,$A1,$A0,$9E,$9D
  .byte $9B,$9A,$99,$97,$96,$92,$8D,$89,$85,$81,$7C,$78,$74,$6F,$6B,$67
  .byte $63,$5E,$5A,$5E,$62,$65,$69,$6D,$70,$74,$78,$7C,$80,$83,$87,$8B
  .byte $8E,$92,$96,$97,$98,$98,$99,$9A,$9B,$9C,$9D,$9E,$9E,$9F,$A0,$A1
  .byte $A2,$A2,$A3,$A4,$A5,$A6,$A7,$A8,$A8,$A9,$AA,$AA,$AA,$AA,$AA,$AA
  .byte $AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA,$AA
  .byte $AA,$A9,$A7,$A6,$A5,$A3,$A2,$A0,$9F,$9E,$9C,$9B,$9A,$98,$97,$96
  .byte $94,$93,$91,$90,$8F,$8D,$8C,$8A,$88,$85,$83,$81,$7F,$7C,$7A,$78
  .byte $76,$74,$71,$6F,$6D,$6B,$68,$66,$64,$66,$68,$6B,$6D,$6F,$71,$73
  .byte $75,$78,$7A,$7C,$7E,$80,$82,$85,$87,$89,$8B,$8D,$8F,$92,$94,$96
PADS0:
  .byte 100,136,2
  .byte 214,244,3
  .byte $FF
PADS1:
  .byte 70,98,2
  .byte 184,212,3
  .byte $FF
PADS2:
  .byte 56,82,2
  .byte 122,146,4
  .byte 196,226,3
  .byte $FF
PADS3:
  .byte 76,100,3
  .byte 180,206,2
  .byte $FF
PADS4:
  .byte 10,36,4
  .byte 84,110,2
  .byte 150,172,5
  .byte $FF
PADS5:
  .byte 70,94,3
  .byte 170,192,5
  .byte $FF

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
; big letters (16x16, 4 tiles each, 8 pattern + 8 colour bytes): L U N A R D E G M O V
BIGFONT:
  .byte $E0,$E0,$E0,$E0,$E0,$E0,$E0,$E0,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $E0,$E0,$E0,$E0,$FF,$FF,$00,$00,$91,$91,$91,$91,$91,$91,$91,$91
  .byte $00,$00,$00,$00,$E0,$E0,$00,$00,$91,$91,$91,$91,$91,$91,$91,$91
  .byte $E0,$E0,$E0,$E0,$E0,$E0,$E0,$E0,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $E0,$E0,$E0,$E0,$E0,$E0,$E0,$E0,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $E0,$E0,$E0,$E0,$3F,$3F,$00,$00,$91,$91,$91,$91,$91,$91,$91,$91
  .byte $E0,$E0,$E0,$E0,$80,$80,$00,$00,$91,$91,$91,$91,$91,$91,$91,$91
  .byte $E0,$E0,$E0,$E0,$F8,$F8,$EE,$EE,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $E0,$E0,$E0,$E0,$E0,$E0,$E0,$E0,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $E3,$E3,$E0,$E0,$E0,$E0,$00,$00,$91,$91,$91,$91,$91,$91,$91,$91
  .byte $E0,$E0,$E0,$E0,$E0,$E0,$00,$00,$91,$91,$91,$91,$91,$91,$91,$91
  .byte $0E,$0E,$3B,$3B,$E0,$E0,$E0,$E0,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $00,$00,$80,$80,$E0,$E0,$E0,$E0,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $FF,$FF,$E0,$E0,$E0,$E0,$00,$00,$91,$91,$91,$91,$91,$91,$91,$91
  .byte $E0,$E0,$E0,$E0,$E0,$E0,$00,$00,$91,$91,$91,$91,$91,$91,$91,$91
  .byte $FF,$FF,$E0,$E0,$E0,$E0,$FF,$FF,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $80,$80,$E0,$E0,$E0,$E0,$80,$80,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $EE,$EE,$E3,$E3,$E0,$E0,$00,$00,$91,$91,$91,$91,$91,$91,$91,$91
  .byte $00,$00,$80,$80,$E0,$E0,$00,$00,$91,$91,$91,$91,$91,$91,$91,$91
  .byte $FF,$FF,$E0,$E0,$E0,$E0,$E0,$E0,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $80,$80,$E0,$E0,$E0,$E0,$E0,$E0,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $E0,$E0,$E0,$E0,$FF,$FF,$00,$00,$91,$91,$91,$91,$91,$91,$91,$91
  .byte $E0,$E0,$E0,$E0,$80,$80,$00,$00,$91,$91,$91,$91,$91,$91,$91,$91
  .byte $FF,$FF,$E0,$E0,$E0,$E0,$FF,$FF,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $E0,$E0,$00,$00,$00,$00,$80,$80,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $E0,$E0,$E0,$E0,$FF,$FF,$00,$00,$91,$91,$91,$91,$91,$91,$91,$91
  .byte $00,$00,$00,$00,$E0,$E0,$00,$00,$91,$91,$91,$91,$91,$91,$91,$91
  .byte $3F,$3F,$E0,$E0,$E0,$E0,$E0,$E0,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $E0,$E0,$00,$00,$00,$00,$00,$00,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $E3,$E3,$E0,$E0,$3F,$3F,$00,$00,$91,$91,$91,$91,$91,$91,$91,$91
  .byte $E0,$E0,$E0,$E0,$E0,$E0,$00,$00,$91,$91,$91,$91,$91,$91,$91,$91
  .byte $E0,$E0,$FB,$FB,$EE,$EE,$EE,$EE,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $E0,$E0,$E0,$E0,$E0,$E0,$E0,$E0,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $E0,$E0,$E0,$E0,$E0,$E0,$00,$00,$91,$91,$91,$91,$91,$91,$91,$91
  .byte $E0,$E0,$E0,$E0,$E0,$E0,$00,$00,$91,$91,$91,$91,$91,$91,$91,$91
  .byte $3F,$3F,$E0,$E0,$E0,$E0,$E0,$E0,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $80,$80,$E0,$E0,$E0,$E0,$E0,$E0,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $E0,$E0,$E0,$E0,$3F,$3F,$00,$00,$91,$91,$91,$91,$91,$91,$91,$91
  .byte $E0,$E0,$E0,$E0,$80,$80,$00,$00,$91,$91,$91,$91,$91,$91,$91,$91
  .byte $E0,$E0,$E0,$E0,$E0,$E0,$E0,$E0,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $E0,$E0,$E0,$E0,$E0,$E0,$E0,$E0,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $3B,$3B,$3B,$3B,$0E,$0E,$00,$00,$91,$91,$91,$91,$91,$91,$91,$91
  .byte $80,$80,$80,$80,$00,$00,$00,$00,$91,$91,$91,$91,$91,$91,$91,$91

; sprites 16x16: 16 lander angles, 16 flame angles, 4 explosion frames x 4 quadrants
SPRITES:
  .byte $00,$01,$03,$07,$0F,$0E,$0F,$0F,$07,$0F,$1F,$1F,$1F,$20,$C0,$C0
  .byte $00,$80,$C0,$E0,$F0,$70,$F0,$F0,$E0,$F0,$F8,$F8,$F8,$04,$03,$03
  .byte $00,$00,$01,$07,$07,$0F,$07,$07,$1F,$3F,$FF,$87,$01,$00,$00,$00
  .byte $00,$20,$E0,$F0,$F8,$38,$F8,$F8,$F0,$E0,$E0,$F0,$E0,$60,$20,$30
  .byte $00,$00,$00,$01,$03,$07,$1F,$FF,$FF,$1F,$0F,$07,$03,$01,$01,$01
  .byte $00,$00,$C0,$F8,$F8,$98,$9C,$FC,$F8,$F0,$E0,$C0,$C0,$80,$80,$80
  .byte $00,$00,$00,$00,$89,$FF,$3F,$1F,$1F,$0F,$0F,$07,$07,$06,$04,$0C
  .byte $00,$00,$00,$F0,$F8,$FE,$DC,$DC,$FC,$F8,$F8,$20,$00,$00,$00,$00
  .byte $C0,$C0,$20,$1C,$1E,$1F,$1F,$1F,$1F,$1F,$1F,$1E,$1C,$20,$C0,$C0
  .byte $00,$00,$00,$00,$F0,$F8,$FC,$DE,$DE,$FC,$F8,$F0,$00,$00,$00,$00
  .byte $0C,$04,$06,$07,$07,$0F,$0F,$1F,$1F,$3F,$FF,$89,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$20,$F8,$F8,$FC,$DC,$DC,$FE,$F8,$F0,$00,$00,$00
  .byte $01,$01,$01,$03,$07,$0F,$1F,$FF,$FF,$1F,$07,$03,$01,$00,$00,$00
  .byte $80,$80,$80,$C0,$C0,$E0,$F0,$F8,$FC,$9C,$98,$F8,$F8,$C0,$00,$00
  .byte $00,$00,$00,$01,$87,$FF,$3F,$1F,$07,$07,$0F,$07,$07,$01,$00,$00
  .byte $30,$20,$60,$E0,$F0,$E0,$E0,$F0,$F8,$F8,$38,$F8,$F0,$E0,$20,$00
  .byte $C0,$C0,$20,$1F,$1F,$1F,$0F,$07,$0F,$0F,$0E,$0F,$07,$03,$01,$00
  .byte $03,$03,$04,$F8,$F8,$F8,$F0,$E0,$F0,$F0,$70,$F0,$E0,$C0,$80,$00
  .byte $0C,$04,$06,$07,$0F,$07,$07,$0F,$1F,$1F,$1C,$1F,$0F,$07,$04,$00
  .byte $00,$00,$00,$80,$E1,$FF,$FC,$F8,$E0,$E0,$F0,$E0,$E0,$80,$00,$00
  .byte $01,$01,$01,$03,$03,$07,$0F,$1F,$3F,$39,$19,$1F,$1F,$03,$00,$00
  .byte $80,$80,$80,$C0,$E0,$F0,$F8,$FF,$FF,$F8,$E0,$C0,$80,$00,$00,$00
  .byte $00,$00,$00,$00,$04,$1F,$1F,$3F,$3B,$3B,$7F,$1F,$0F,$00,$00,$00
  .byte $30,$20,$60,$E0,$E0,$F0,$F0,$F8,$F8,$FC,$FF,$91,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$0F,$1F,$3F,$7B,$7B,$3F,$1F,$0F,$00,$00,$00,$00
  .byte $03,$03,$04,$38,$78,$F8,$F8,$F8,$F8,$F8,$F8,$78,$38,$04,$03,$03
  .byte $00,$00,$00,$0F,$1F,$7F,$3B,$3B,$3F,$1F,$1F,$04,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$91,$FF,$FC,$F8,$F8,$F0,$F0,$E0,$E0,$60,$20,$30
  .byte $00,$00,$03,$1F,$1F,$19,$39,$3F,$1F,$0F,$07,$03,$03,$01,$01,$01
  .byte $00,$00,$00,$80,$C0,$E0,$F8,$FF,$FF,$F8,$F0,$E0,$C0,$80,$80,$80
  .byte $00,$04,$07,$0F,$1F,$1C,$1F,$1F,$0F,$07,$07,$0F,$07,$06,$04,$0C
  .byte $00,$00,$80,$E0,$E0,$F0,$E0,$E0,$F8,$FC,$FF,$E1,$80,$00,$00,$00
  .byte $07,$07,$07,$07,$07,$07,$03,$03,$03,$03,$03,$01,$01,$01,$01,$00
  .byte $E0,$E0,$E0,$E0,$E0,$E0,$C0,$C0,$C0,$C0,$C0,$80,$80,$80,$80,$00
  .byte $00,$01,$01,$01,$01,$03,$03,$03,$03,$03,$07,$07,$06,$04,$04,$00
  .byte $C0,$F0,$FC,$F8,$F8,$F0,$E0,$E0,$C0,$80,$80,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$01,$01,$03,$07,$07,$0F,$0C,$10,$00,$00,$00
  .byte $00,$30,$38,$7C,$FE,$FE,$F8,$F0,$E0,$80,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$01,$07,$0F,$1F,$7C,$00,$00,$00,$00,$00
  .byte $00,$00,$04,$1C,$3E,$FE,$FF,$FF,$FE,$E0,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$07,$7F,$7F,$07,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$3F,$FF,$FF,$FF,$FF,$3F,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$7C,$1F,$0F,$07,$01,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$E0,$FE,$FF,$FF,$FE,$3E,$1C,$04,$00,$00
  .byte $00,$00,$00,$10,$0C,$0F,$07,$07,$03,$01,$01,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$80,$E0,$F0,$F8,$FE,$FE,$7C,$38,$30,$00
  .byte $00,$04,$04,$06,$07,$07,$03,$03,$03,$03,$03,$01,$01,$01,$01,$00
  .byte $00,$00,$00,$00,$00,$80,$80,$C0,$E0,$E0,$F0,$F8,$F8,$FC,$F0,$C0
  .byte $00,$01,$01,$01,$01,$03,$03,$03,$03,$03,$07,$07,$07,$07,$07,$07
  .byte $00,$80,$80,$80,$80,$C0,$C0,$C0,$C0,$C0,$E0,$E0,$E0,$E0,$E0,$E0
  .byte $00,$00,$00,$00,$00,$01,$01,$03,$07,$07,$0F,$1F,$1F,$3F,$0F,$03
  .byte $00,$20,$20,$60,$E0,$E0,$C0,$C0,$C0,$C0,$C0,$80,$80,$80,$80,$00
  .byte $00,$00,$00,$00,$00,$00,$01,$07,$0F,$1F,$7F,$7F,$3E,$1C,$0C,$00
  .byte $00,$00,$00,$08,$30,$F0,$E0,$E0,$C0,$80,$80,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$07,$7F,$FF,$FF,$7F,$7C,$38,$20,$00,$00
  .byte $00,$00,$00,$00,$00,$3E,$F8,$F0,$E0,$80,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$FC,$FF,$FF,$FF,$FF,$FC,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$E0,$FE,$FE,$E0,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$20,$38,$7C,$7F,$FF,$FF,$7F,$07,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$80,$E0,$F0,$F8,$3E,$00,$00,$00,$00,$00
  .byte $00,$0C,$1C,$3E,$7F,$7F,$1F,$0F,$07,$01,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$80,$80,$C0,$E0,$E0,$F0,$30,$08,$00,$00,$00
  .byte $03,$0F,$3F,$1F,$1F,$0F,$07,$07,$03,$01,$01,$00,$00,$00,$00,$00
  .byte $00,$80,$80,$80,$80,$C0,$C0,$C0,$C0,$C0,$E0,$E0,$60,$20,$20,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$06,$17,$05,$4F,$7F,$3F,$BF,$7F,$BF
  .byte $00,$00,$00,$00,$00,$00,$00,$A0,$D8,$78,$EE,$F9,$F8,$FF,$FC,$FC
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $3F,$3F,$7F,$FF,$1F,$4F,$1E,$01,$07,$00,$00,$00,$00,$00,$00,$00
  .byte $FD,$FF,$FF,$FB,$FB,$FC,$04,$D8,$E0,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$01,$00,$03,$06,$07,$07,$07,$07
  .byte $00,$00,$00,$00,$00,$1F,$2F,$FB,$7F,$FF,$DB,$DF,$FF,$FD,$FA,$F8
  .byte $00,$00,$00,$00,$00,$F8,$F8,$FF,$FA,$FF,$FD,$FF,$FF,$2D,$5F,$FF
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$80,$C0,$E0,$E0,$E0,$E0,$E0
  .byte $07,$07,$07,$03,$07,$03,$01,$01,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $DF,$F9,$FE,$FF,$7F,$FF,$FB,$FF,$DD,$3F,$1F,$00,$00,$00,$00,$00
  .byte $3F,$7E,$7E,$FF,$FF,$FF,$FF,$FC,$EF,$FC,$78,$00,$00,$00,$00,$00
  .byte $E0,$E0,$60,$E0,$E0,$C0,$80,$80,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$01,$03,$07,$0F,$1C,$19,$1D,$2C,$2E,$6F,$7B,$1B,$6F
  .byte $00,$17,$7C,$37,$67,$D9,$0F,$FF,$E9,$E0,$F4,$18,$86,$91,$C6,$16
  .byte $00,$E8,$1A,$9F,$FC,$F1,$07,$CF,$AD,$4B,$8E,$04,$20,$0B,$53,$07
  .byte $00,$00,$00,$80,$C0,$80,$40,$38,$78,$F8,$98,$1C,$5C,$D6,$DA,$2E
  .byte $6C,$4D,$7D,$57,$57,$3F,$1F,$3F,$18,$0C,$0F,$01,$00,$00,$00,$00
  .byte $C4,$40,$11,$CE,$D0,$B7,$6C,$0E,$22,$71,$7E,$BE,$DA,$ED,$03,$00
  .byte $14,$09,$08,$29,$1D,$0D,$3C,$CF,$EF,$DE,$D3,$77,$1D,$C7,$76,$00
  .byte $7E,$3E,$4C,$68,$B6,$A4,$48,$88,$B8,$00,$A0,$40,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$04,$00,$00,$00,$00,$10
  .byte $02,$00,$18,$18,$A8,$04,$01,$01,$00,$C0,$D8,$18,$18,$40,$60,$60
  .byte $20,$00,$00,$30,$30,$00,$80,$80,$00,$00,$00,$00,$06,$06,$0C,$0C
  .byte $00,$00,$00,$00,$00,$00,$40,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$01,$08,$00,$04,$10,$05,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $40,$00,$00,$00,$00,$00,$00,$00,$01,$01,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$C0,$80,$00,$40,$00,$00,$00,$00
  .byte $00,$80,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00

; ---- AY periods (1 MHz): TP = 62500 / f.  index = MIDI note - 35 (1 = C2 ... 55 = F#6), 0 = rest
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
V0_TAB:        .byte 13, 9, 12, 0      ; volume at the attack of the note (melody, arpeggio, bass)
FLOOR_TAB:     .byte 9, 4, 8, 0        ; lowest volume reached by the decay
DECMASK_TAB:   .byte 7, 3, 3, 0        ; the volume drops by 1 when (age AND mask) = 0
VIB_TAB:       .byte 0, 1, 1, 0, 0, $FF, $FF, 0   ; vibrato +-1 step (signed)
; drums: 1 kick, 2 snare, 3 hi-hat, 4 cymbal
DRUM_NP:       .byte 0, 28, 10, 2, 5
DRUM_V0:       .byte 0, 15, 14, 8, 15
DRUM_MASK:     .byte 0, 0, 0, 0, 7
; songs: lead, arpeggio, bass, drums = .byte note,frames ... $FF   (0 = rest)
; order: title (CMD_TITLE), game over (CMD_LOSE), victory (CMD_WIN), crash (CMD_CRASH)
TITLE_LEAD:
  .byte $29,$1E,$27,$0F,$25,$0F,$25,$1E,$22,$1E,$29,$0F,$2C,$0F,$29,$1E
  .byte $27,$1E,$24,$1E,$25,$0F,$29,$0F,$2E,$1E,$2E,$3C,$FF
TITLE_HARM:
  .byte $16,$07,$19,$08,$1D,$07,$19,$08,$16,$07,$19,$08,$1D,$07,$19,$08
  .byte $12,$07,$16,$08,$19,$07,$16,$08,$12,$07,$16,$08,$19,$07,$16,$08
  .byte $19,$07,$1D,$08,$20,$07,$1D,$08,$19,$07,$1D,$08,$20,$07,$1D,$08
  .byte $14,$07,$18,$08,$1B,$07,$18,$08,$14,$07,$18,$08,$1B,$07,$18,$08
  .byte $16,$07,$19,$08,$1D,$07,$19,$08,$16,$07,$19,$08,$1D,$07,$19,$08
  .byte $16,$07,$19,$08,$1D,$07,$19,$08,$16,$07,$19,$08,$1D,$07,$19,$08
  .byte $FF
TITLE_BASS:
  .byte $0A,$1E,$0A,$1E,$06,$1E,$06,$1E,$0D,$1E,$0D,$1E,$08,$1E,$08,$1E
  .byte $0A,$1E,$0A,$1E,$0A,$3C,$FF
TITLE_DRUM:
  .byte $01,$0F,$03,$0F,$02,$0F,$03,$0F,$01,$0F,$03,$0F,$02,$0F,$03,$0F
  .byte $01,$0F,$03,$0F,$02,$0F,$03,$0F,$01,$0F,$03,$0F,$02,$0F,$03,$0F
  .byte $01,$0F,$03,$0F,$02,$0F,$03,$0F,$04,$3C,$FF
OVER_LEAD:
  .byte $29,$24,$25,$12,$27,$12,$2A,$24,$27,$12,$22,$12,$24,$24,$21,$12
  .byte $24,$12,$22,$48,$FF
OVER_HARM:
  .byte $19,$09,$1D,$09,$22,$09,$1D,$09,$19,$09,$1D,$09,$22,$09,$1D,$09
  .byte $1B,$09,$1E,$09,$22,$09,$1E,$09,$1B,$09,$1E,$09,$22,$09,$1E,$09
  .byte $1D,$09,$21,$09,$24,$09,$21,$09,$1D,$09,$21,$09,$24,$09,$21,$09
  .byte $19,$09,$1D,$09,$22,$09,$1D,$09,$19,$09,$1D,$09,$22,$09,$1D,$09
  .byte $FF
OVER_BASS:
  .byte $0A,$24,$0A,$24,$03,$24,$03,$24,$05,$24,$05,$24,$0A,$48,$FF
OVER_DRUM:
  .byte $01,$12,$03,$12,$02,$12,$03,$12,$01,$12,$03,$12,$02,$12,$03,$12
  .byte $01,$12,$03,$12,$02,$12,$03,$12,$04,$48,$FF
WIN_LEAD:
  .byte $25,$08,$29,$08,$2C,$08,$31,$18,$33,$0C,$30,$0C,$2C,$0C,$27,$0C
  .byte $29,$0C,$2C,$0C,$31,$0C,$35,$0C,$31,$0C,$35,$24,$FF
WIN_HARM:
  .byte $19,$08,$1D,$08,$20,$08,$1D,$08,$19,$08,$1D,$08,$14,$08,$18,$08
  .byte $1B,$08,$18,$08,$14,$08,$18,$08,$19,$08,$1D,$08,$20,$08,$25,$08
  .byte $20,$08,$1D,$08,$19,$08,$1D,$08,$20,$08,$25,$08,$20,$08,$1D,$08
  .byte $FF
WIN_BASS:
  .byte $0D,$18,$0D,$18,$08,$18,$08,$18,$0D,$30,$0D,$30,$FF
WIN_DRUM:
  .byte $01,$0C,$03,$0C,$02,$0C,$03,$0C,$01,$0C,$03,$0C,$02,$0C,$03,$0C
  .byte $01,$0C,$03,$0C,$02,$0C,$03,$0C,$01,$0C,$03,$0C,$02,$0C,$04,$0C
  .byte $FF
CRASH_LEAD:
  .byte $29,$0E,$28,$0E,$27,$0E,$25,$0E,$20,$3C,$FF
CRASH_HARM:
  .byte $1D,$0E,$1C,$0E,$1B,$0E,$19,$0E,$14,$3C,$FF
CRASH_BASS:
  .byte $0A,$1C,$09,$1C,$08,$1C,$05,$20,$FF
CRASH_DRUM:
  .byte $01,$1C,$00,$1C,$01,$1C,$04,$20,$FF
SONGP_LO:      .byte <TITLE_LEAD,<TITLE_HARM,<TITLE_BASS,<TITLE_DRUM,<OVER_LEAD,<OVER_HARM,<OVER_BASS,<OVER_DRUM,<WIN_LEAD,<WIN_HARM,<WIN_BASS,<WIN_DRUM,<CRASH_LEAD,<CRASH_HARM,<CRASH_BASS,<CRASH_DRUM
SONGP_HI:      .byte >TITLE_LEAD,>TITLE_HARM,>TITLE_BASS,>TITLE_DRUM,>OVER_LEAD,>OVER_HARM,>OVER_BASS,>OVER_DRUM,>WIN_LEAD,>WIN_HARM,>WIN_BASS,>WIN_DRUM,>CRASH_LEAD,>CRASH_HARM,>CRASH_BASS,>CRASH_DRUM
; one-shot tone effects: period and volume for every frame
WH_TL:
  .byte $18,$1C,$20,$50,$50,$50,$50,$50,$50,$30,$30,$50,$50,$30,$30,$50
  .byte $50,$20,$27,$2E,$35,$3C,$43,$4A,$51,$58,$5F,$66,$6D,$74,$7B,$82
  .byte $89,$90,$97,$9E,$A5,$A0,$A0,$A0,$78,$78,$78,$5F,$5F,$5F,$50,$50
  .byte $50,$50,$90,$90,$78,$78,$60,$60,$50,$50
WH_TH:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00
WH_VOL:
  .byte $09,$06,$03,$0C,$0C,$0C,$0C,$08,$04,$0B,$0B,$0B,$0B,$0B,$0B,$0B
  .byte $0B,$0C,$0C,$0B,$0B,$0A,$0A,$09,$09,$08,$08,$07,$07,$06,$06,$05
  .byte $05,$04,$04,$03,$03,$0A,$0A,$0A,$0A,$0A,$0A,$0B,$0B,$0B,$0C,$0C
  .byte $0C,$0C,$0B,$0B,$0B,$0B,$0B,$0B,$09,$05
WH_START:
  .byte $00,$00,$03,$09,$11,$25,$32
WH_LEN:
  .byte $00,$03,$06,$08,$14,$0D,$08
W_ROT = 1
W_LOW = 2
W_ALARM = 3
W_NOFUEL = 4
W_START = 5
W_LAND = 6
; explosions: id 1 small (20 frames), id 2 big (62 frames), id 3 touchdown thud (10 frames)
EX_NV:
  .byte $0F,$0E,$0D,$0C,$0B,$0A,$09,$08,$07,$06,$05,$04,$03,$03,$02,$02
  .byte $01,$01,$00,$00,$0F,$0F,$0F,$0F,$0E,$0E,$0D,$0D,$0C,$0C,$0C,$0C
  .byte $0B,$0B,$0A,$0A,$0A,$0A,$09,$09,$09,$09,$08,$08,$08,$08,$07,$07
  .byte $06,$06,$06,$06,$05,$05,$05,$05,$04,$04,$04,$04,$03,$03,$03,$03
  .byte $03,$03,$02,$02,$02,$02,$01,$01,$01,$01,$01,$01,$00,$00,$00,$00
  .byte $00,$00,$0C,$0A,$08,$06,$04,$03,$02,$01,$00,$00
EX_NP:
  .byte $04,$05,$06,$07,$08,$09,$0A,$0B,$0C,$0D,$0E,$0F,$10,$11,$12,$13
  .byte $14,$15,$16,$17,$03,$03,$05,$05,$07,$07,$08,$08,$09,$09,$0A,$0A
  .byte $0B,$0B,$0C,$0C,$0D,$0D,$0E,$0E,$0F,$0F,$0F,$0F,$10,$10,$11,$11
  .byte $12,$12,$12,$12,$13,$13,$14,$14,$14,$14,$15,$15,$16,$16,$16,$16
  .byte $17,$17,$18,$18,$18,$18,$19,$19,$1A,$1A,$1A,$1A,$1B,$1B,$1B,$1B
  .byte $1C,$1C,$12,$13,$14,$15,$16,$17,$18,$19,$1A,$1B
EX_VC:
  .byte $0C,$0C,$0B,$0A,$09,$08,$07,$06,$06,$05,$04,$03,$02,$01,$00,$00
  .byte $00,$00,$00,$00,$0E,$0E,$0D,$0D,$0D,$0D,$0C,$0C,$0C,$0C,$0B,$0B
  .byte $0A,$0A,$0A,$0A,$09,$09,$09,$09,$08,$08,$08,$08,$07,$07,$06,$06
  .byte $06,$06,$05,$05,$05,$05,$04,$04,$04,$04,$03,$03,$02,$02,$02,$02
  .byte $01,$01,$01,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$0D,$0B,$09,$07,$05,$03,$02,$01,$00,$00
EX_TL:
  .byte $08,$26,$44,$62,$80,$9E,$BC,$DA,$F8,$16,$34,$52,$70,$8E,$AC,$CA
  .byte $E8,$06,$24,$42,$C8,$C8,$D6,$D6,$E5,$E5,$F5,$F5,$06,$06,$18,$18
  .byte $2B,$2B,$40,$40,$56,$56,$6E,$6E,$87,$87,$A3,$A3,$C0,$C0,$DF,$DF
  .byte $00,$00,$24,$24,$4A,$4A,$72,$72,$9E,$9E,$CD,$CD,$FE,$FE,$34,$34
  .byte $6C,$6C,$A9,$A9,$EA,$EA,$30,$30,$7B,$7B,$CA,$CA,$1F,$1F,$7B,$7B
  .byte $DC,$DC,$80,$90,$A0,$B0,$C0,$D0,$E0,$F0,$00,$10
EX_TH:
  .byte $02,$02,$02,$02,$02,$02,$02,$02,$02,$03,$03,$03,$03,$03,$03,$03
  .byte $03,$04,$04,$04,$00,$00,$00,$00,$00,$00,$00,$00,$01,$01,$01,$01
  .byte $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
  .byte $02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$03,$03
  .byte $03,$03,$03,$03,$03,$03,$04,$04,$04,$04,$04,$04,$05,$05,$05,$05
  .byte $05,$05,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02
EX_START:      .byte 0,0,20,82
EX_LEN:        .byte 0,20,62,10

TXT_HUD:
  .byte 0,0,15,$53,$43,$4F,$52,$45,0   ; "SCORE"
  .byte 0,13,15,$48,$49,0   ; "HI"
  .byte 0,23,11,$4C,$56,0   ; "LV"
  .byte 0,30,11,$58,0   ; "X"
  .byte 1,0,15,$46,$55,$45,$4C,0   ; "FUEL"
  .byte 1,10,15,$41,$4C,$54,0   ; "ALT"
  .byte 1,18,15,$48,$53,0   ; "HS"
  .byte 1,25,15,$56,$53,0   ; "VS"
  .byte $FF
TXT_TITLE:
  .byte 1,8,15,$48,$49,$20,$53,$43,$4F,$52,$45,0   ; "HI SCORE"
  .byte 9,6,11,$4C,$45,$46,$54,$2F,$52,$49,$47,$48,$54,$20,$3D,$20,$52,$4F,$54,$41,$54,$45,0   ; "LEFT/RIGHT = ROTATE"
  .byte 10,6,11,$55,$50,$20,$4F,$52,$20,$42,$55,$54,$54,$4F,$4E,$20,$3D,$20,$54,$48,$52,$55,$53,$54,0   ; "UP OR BUTTON = THRUST"
  .byte 12,6,3,$4C,$41,$4E,$44,$20,$53,$4C,$4F,$57,$4C,$59,$20,$4F,$4E,$20,$41,$20,$46,$4C,$41,$54,$20,$50,$41,$44,0   ; "LAND SLOWLY ON A FLAT PAD"
  .byte 13,6,3,$53,$4D,$41,$4C,$4C,$20,$50,$41,$44,$53,$20,$50,$41,$59,$20,$4D,$4F,$52,$45,0   ; "SMALL PADS PAY MORE"
  .byte 15,9,14,$50,$52,$45,$53,$53,$20,$41,$20,$42,$55,$54,$54,$4F,$4E,0   ; "PRESS A BUTTON"
  .byte $FF
TXT_LEVEL:
  .byte 5,12,11,$4C,$45,$56,$45,$4C,0   ; "LEVEL"
  .byte 7,11,15,$47,$45,$54,$20,$52,$45,$41,$44,$59,0   ; "GET READY"
  .byte $FF
TXT_BLANK1:
  .byte 5,12,15,$20,$20,$20,$20,$20,$20,$20,$20,0   ; "        "
  .byte 7,11,15,$20,$20,$20,$20,$20,$20,$20,$20,$20,0   ; "         "
  .byte $FF
TXT_LAND:
  .byte 4,7,3,$53,$55,$43,$43,$45,$53,$53,$46,$55,$4C,$20,$4C,$41,$4E,$44,$49,$4E,$47,0   ; "SUCCESSFUL LANDING"
  .byte 6,12,15,$50,$41,$44,$20,$58,0   ; "PAD X"
  .byte 8,11,15,$42,$4F,$4E,$55,$53,0   ; "BONUS"
  .byte $FF
TXT_CRASH:
  .byte 4,11,8,$43,$52,$41,$53,$48,$45,$44,$21,0   ; "CRASHED!"
  .byte $FF
TXT_R0:
  .byte $FF
TXT_R1:
  .byte 6,12,9,$54,$4F,$4F,$20,$46,$41,$53,$54,0   ; "TOO FAST"
  .byte $FF
TXT_R2:
  .byte 6,11,9,$42,$41,$44,$20,$41,$4E,$47,$4C,$45,0   ; "BAD ANGLE"
  .byte $FF
TXT_R3:
  .byte 6,8,9,$4C,$41,$4E,$44,$45,$44,$20,$4F,$4E,$20,$52,$4F,$43,$4B,$53,0   ; "LANDED ON ROCKS"
  .byte $FF
TXT_OVER:
  .byte 11,9,15,$53,$43,$4F,$52,$45,0   ; "SCORE"
  .byte 13,8,15,$48,$49,$20,$53,$43,$4F,$52,$45,0   ; "HI SCORE"
  .byte $FF
TXT_PRESS:
  .byte 16,9,14,$50,$52,$45,$53,$53,$20,$41,$20,$42,$55,$54,$54,$4F,$4E,0   ; "PRESS A BUTTON"
  .byte $FF
TITLE_BIG:
  .byte 3,11,5,0,1,2,3,4   ; LUNAR
  .byte 6,10,6,0,3,2,5,6,4   ; LANDER
  .byte $FF
OVER_BIG:
  .byte 4,12,4,7,3,8,6   ; GAME
  .byte 7,12,4,9,10,6,4   ; OVER
  .byte $FF
