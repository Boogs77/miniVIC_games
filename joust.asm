;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;                                                              ;
;   ARCADE_JOUST  -  Williams Joust (1982)                     ;
;   65C02 assembly, TMS9918A Graphics II (tiles + sprites)     ;
;   Base: moon cresta (VDP, NMI + trampoline $0FD0, AY engine) ;
;   and lunar lander (8.8 fixed point physics)                 ;
;                                                              ;
;   - a knight on an ostrich: LEFT / RIGHT = run and fly in    ;
;     that direction, button = flap the wings (tap it to       ;
;     climb). The field wraps at the left and right edges      ;
;   - 1 or 2 players at the same time: title button 1 = 1      ;
;     player (both joysticks drive him), button 2 = 2 players  ;
;     (joystick 1 = ostrich, joystick 2 = stork)               ;
;   - when two riders touch, the one that is higher wins;      ;
;     at the same height they bounce apart                     ;
;   - Bounder 500, Hunter 750, Shadow Lord 1500, Pterodactyl   ;
;     1000 (hit it in the beak). A defeated rider leaves an    ;
;     egg: pick it up before it hatches: 250, 500, 750, 1000   ;
;     in a row (+500 if caught in the air); the row starts     ;
;     again after you lose a rider. A hatched egg calls a      ;
;     buzzard and comes back as a better rider                 ;
;   - 5 riders to start, an extra one every 20000 points.      ;
;     Unseating the other player: 50 points                    ;
;   - waves of a cycle of 5: normal, SURVIVAL (3000 to who     ;
;     does not die) or TEAM (3000 each if nobody hits the      ;
;     other), normal (the PTERODACTYL wave from wave 8),       ;
;     GLADIATOR (3000 to the first who unseats the other),     ;
;     EGG WAVE. The platforms come back all together every 5   ;
;     waves; the bridge over the lava burns from wave 3 on;    ;
;     the hand of the troll grabs who flies low over the lava  ;
;   - SOUND (2 x AY-3-8910, played from the NMI at 60 Hz):     ;
;     flap, steps, joust, eggs, hatching, pterodactyl, troll,  ;
;     lava, wave tune, extra rider                             ;
;   - the main loop writes the VDP only with the interrupt     ;
;     off (VDP_INT_OFF just after the NMI); the NMI only       ;
;     copies the SAT during the vblank and plays the sound     ;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; ---------------- zero page: game ----------------
NPL         = $30      ; number of players (1-2)
WAVEN       = $31      ; wave number (1-99)
WTYPE       = $32      ; 0 normal, 1 survival, 2 team, 3 gladiator, 4 egg, 5 pterodactyl
WSTATE      = $33      ; 0 banner, 1 playing, 2 wave over
MSGT        = $34      ; frames of the banner
WTL         = $35      ; frames in the wave (16 bit)
WTH         = $36
QB          = $37      ; riders still to come: bounders, hunters, shadow lords
QH          = $38
QS          = $39
QSPAWN      = $3A      ; frames to the next rider
QIDX        = $3B
NALIVE      = $3C      ; riders on the field (or about to come)
NEGGS       = $3D      ; eggs on the field
MAXLIVE     = $3E      ; riders at the same time
OVERT       = $3F      ; frames of the end of the wave
TEAMHIT     = $40      ; 1 = a player hit the other (team wave lost)
GLADEND     = $41      ; 1 = the gladiator bonus was given
BRN_T       = $42      ; bridge: units of 4 frames before the next tile burns
BR_BT       = $43      ; bridge: frames the tile burns (0 = none)
BR_BSIDE    = $44      ; bridge: side of the burning tile (0 left, 1 right)
BR_L        = $45      ; bridge: tiles gone on the left (0-9)
BR_R        = $46      ;                       on the right
BR_TOG      = $47      ; next side to burn
LAVAPH      = $48      ; phase of the lava crests
BANNER      = $49      ; 1 = a message is on the screen
TRY         = $4A      ; attempts (spawn)
CMDONE      = $4B      ; players taking part (bit 0 = P1, bit 1 = P2)
PTHIT       = $4C
NEAR        = $4D      ; nearest player (AI)
NDX         = $4E      ; |dx| to him
NDY         = $4F      ; his Y
SCDIRTY     = $50      ; bit per player: score or riders changed
CI          = $51      ; creature / egg being handled
CJ          = $52
FLAPQ       = $53      ; 1 = this creature flaps now
WINNER      = $54
ENDW        = $55

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
TP          = $72      ; 2 bytes: text records
P_JOY       = $7E      ; 2 bytes (joystick, 1 = pressed)

LIVES       = $80      ; 2 bytes: riders left (the one playing included)
SCL         = $82      ; 2 bytes: score per player (BCD): tens and units
SCM         = $84      ; thousands and hundreds
SCH         = $86      ; hundred thousands and ten thousands
HISC        = $88      ; 3 bytes BCD (low, middle, high)
NXL         = $8B      ; 2 bytes: next extra rider (BCD high digits of the score)
CHAIN       = $8D      ; 2 bytes: eggs picked up in a row
DIED        = $8F      ; 2 bytes: 1 = lost a rider in this wave
P_OLD       = $91      ; 2 bytes: buttons of the previous frame
PTS_L       = $93      ; points to add (BCD)
PTS_M       = $94
PQX         = $96      ; PLAT_COLL: position, old Y, vertical speed (sign), half sizes, result
PQY         = $97
PQO         = $98
PQV         = $99
PQW         = $9A
PQH         = $9B
PQR         = $9C
DXV         = $9D
DYV         = $9E
RR          = $9F      ; first creature in the SAT (turns)
SATB        = $A0      ; bytes of the SAT to copy
KILLER      = $A1

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
OX         = $E0         ; sprite being added: X on the screen, Y, pattern, colour
OY         = $E1
ON         = $E2
OC         = $E3
SPRI       = $E4         ; next free byte of the SAT

WH_ID      = $0700       ; tone effect playing per chip (0 = none)  2 bytes
WH_POS     = $0702       ; frames elapsed
EX_ID      = $0704       ; explosion playing per chip (S_*)
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
CMD_START  = 2           ; the start tune

; ---------------- creatures: slots 0-1 players, 2-9 riders on buzzards
NC         = 10
C_ST       = $0300       ; 0 free, 1 flying / walking, 2 dying, 3 coming (sparkle), 4 buzzard fetching its rider, 5 held by the troll
C_TY       = $030A       ; 0 player, 1 bounder, 2 hunter, 3 shadow lord
C_XL       = $0314       ; centre X 8.8 (the field wraps)
C_XH       = $031E
C_YL       = $0328       ; centre Y 8.8
C_YH       = $0332
C_VXL      = $033C       ; velocity 8.8 signed
C_VXH      = $0346
C_VYL      = $0350
C_VYH      = $035A
C_FACE     = $0364       ; 0 right, 1 left
C_GND      = $036E       ; 1 = standing on a platform
C_T        = $0378       ; timer of the state (dying, coming, safe time of a player)
C_AT       = $0382       ; frames before the rider thinks again
C_TGY      = $038C       ; height he wants
C_DIR      = $0396       ; 0 none, 1 right, 2 left
C_FLT      = $03A0       ; frames of the wings up
C_EGG      = $03AA       ; egg the buzzard comes for (egg + 1, 0 = none)
C_ANIM     = $03B4       ; steps

; ---------------- eggs
NEG        = 8
E_ST       = $03C0       ; 0 free, 1 falling, 2 resting, 3 hatching
E_XL       = $03C8
E_XH       = $03D0
E_YL       = $03D8
E_YH       = $03E0
E_VXL      = $03E8
E_VXH      = $03F0
E_VYL      = $03F8
E_VYH      = $0400
E_T        = $0408       ; hatching clock (units of 4 frames)
E_TY       = $0410       ; kind of rider inside
E_PEN      = $0418       ; buzzard coming (slot, 0 = none yet)

; ---------------- platforms
NPF        = 9
PF_ON      = $0420
PF_X1      = $0429       ; left pixel
PF_X2      = $0432       ; right pixel (included)
PF_Y       = $043B       ; top pixel
E_GR       = $0444       ; frames before an egg can be picked up (8 bytes)

; ---------------- small effects (explosions, sparkles)
NFX        = 6
FX_T       = $0450       ; frames left (0 = free)
FX_X       = $0456
FX_Y       = $045C
FX_K       = $0462       ; 0 explosion, 1 sparkle

; ---------------- pterodactyl and troll
PT_ST      = $0470       ; 0 none, 1 flying
PT_XL      = $0471
PT_XH      = $0472
PT_YL      = $0473
PT_YH      = $0474
PT_VXL     = $0475
PT_VXH     = $0476
PT_VYL     = $0477
PT_VYH     = $0478
PT_T       = $0479
PT_FACE    = $047A
TR_ST      = $0480       ; troll: 0 none, 1 hand coming up, 2 holds, 3 going down
TR_X       = $0481
TR_T       = $0482
TR_C       = $0483       ; creature held
TR_CD      = $0484       ; frames before it can act again
TR_H       = $0485       ; how high the hand came out
DSL        = $A2         ; creature being drawn

SAT_BUFFER = $0600       ; 32 sprites x 4 + end of list

; ---------------- parameters ----------------
INIT_LIVES  = 5
GRAV        = $0012      ; 8.8 pixels per frame per frame
FLAP_V      = $0128      ; speed given by a flap
VUP_MAX     = $0300
VUP_NEG     = $10000-VUP_MAX
GRAB_Y      = 146        ; the troll reaches a centre this low over the lava
VDN_MAX     = $0300
FR_GND      = $0020      ; friction on a platform
FR_AIR      = $0004      ; friction in the air
HWC         = 6          ; half width and half height of a rider
HHC         = 8
CEIL_Y      = 30         ; highest centre
LAVA_CY     = 170        ; centre Y of a rider in the lava
BTN_MASK    = %00110000
SAFE_T      = 150        ; frames of safety of a new player
FLAP_ANIM   = 8

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
  STA VINT                     ; VDP interrupt off (R1 = $C6)
  STA FRAME_CNT
  STA LAST_FRAME
  STA HISC
  STA HISC+1
  STA HISC+2
  STA LAVAPH
  STA BANNER
  LDX #$01
.rs_p:
  STZ SCL,X
  STZ SCM,X
  STZ SCH,X
  STZ LIVES,X
  STZ P_OLD,X
  DEX
  BPL .rs_p
  LDA #$A5
  STA RND
  JSR HIDE_SPRITES
  JMP TITLE


; ===============================================================
;  TITLE: the scoring table; button 1 = 1 player, 2 = 2 players
; ===============================================================
TITLE:
  LDX #$FF
  TXS
  JSR HIDE_SPRITES
  LDA #CMD_GAME
  STA SND_CMD
  JSR VDP_INT_OFF
  JSR CLEAR_NT
  JSR DRAW_LAVA
  JSR DRAW_LAVA_DEEP
  JSR DRAW_TOP
  LDA #<TXT_BIG
  STA TP
  LDA #>TXT_BIG
  STA TP+1
  JSR PRINT
  LDA #<TXT_TITLE
  STA TP
  LDA #>TXT_TITLE
  STA TP+1
  JSR PRINT
  LDX #$00                     ; the riders of the table (sprites)
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
  CPX #8
  BNE .ti_s
  LDA #$D0
  STA SAT_BUFFER,Y
  INY
  STY SATB
  JSR VDP_INT_ON
.t_rel:                        ; buttons released...
  JSR WAIT_FRAME
  JSR LAVA_TICK
  JSR READ_JOY
  LDA P_JOY
  ORA P_JOY+1
  AND #BTN_MASK
  BNE .t_rel
.t_press:                      ; ...then button 1 = 1 player, button 2 = 2 players
  JSR WAIT_FRAME
  JSR LAVA_TICK
  JSR READ_JOY
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
  ; fall into NEW_GAME


; ===============================================================
;  NEW GAME: wave 1, 5 riders for every player
; ===============================================================
NEW_GAME:
  LDX #$01
.ng_p:
  STZ SCL,X
  STZ SCM,X
  STZ SCH,X
  STZ CHAIN,X
  STZ DIED,X
  STZ P_OLD,X
  STZ C_ST,X
  LDA #$02
  STA NXL,X
  LDA #INIT_LIVES
  STA LIVES,X
  DEX
  BPL .ng_p
  LDA NPL
  CMP #$02
  BEQ .ng_2
  STZ LIVES+1
.ng_2:
  LDA #$01
  STA WAVEN
  STZ BR_L
  STZ BR_R
  LDA #CMD_START
  STA SND_CMD
  ; fall into WAVE_START


; ===============================================================
;  WAVE START: platforms, enemies to come, banner
; ===============================================================
WAVE_START:
  LDX #$FF
  TXS
  JSR HIDE_SPRITES
  JSR VDP_INT_OFF
  JSR CLEAR_OBJECTS
  JSR SET_WAVE
  JSR SET_PLATFORMS
  JSR CLEAR_NT
  JSR DRAW_FIELD
  JSR PLACE_PLAYERS
  LDA WTYPE
  CMP #4
  BNE .ws_ne
  JSR SPAWN_EGGWAVE
.ws_ne:
  JSR SHOW_BANNER
  JSR BUILD_SAT
  JSR VDP_INT_ON
  LDA SND_BUSY                 ; the start tune of the game, to the end
  BEQ .ws_jingle
.ws_tune:
  JSR WAIT_FRAME
  LDA SND_BUSY
  BNE .ws_tune
  BRA .ws_go
.ws_jingle:
  LDA #W_WAVE
  LDX #2
  JSR SFX_WHISTLE
.ws_go:
  STZ WSTATE
  LDA #150
  STA MSGT
  LDA #60
  STA QSPAWN
  ; fall into GAME_LOOP


; ===============================================================
;  GAME LOOP: one pass = one frame
; ===============================================================
GAME_LOOP:
  JSR VDP_INT_OFF              ; waits for the vblank and frees the VDP
  JSR READ_JOY
  JSR NEXT_RND
  JSR ANIM_LAVA
  JSR UPDATE_PLAYERS
  JSR UPDATE_ENEMIES
  JSR COLLIDE
  JSR UPDATE_EGGS
  JSR UPDATE_PTERO
  JSR UPDATE_TROLL
  JSR UPDATE_BRIDGE
  JSR UPDATE_FX
  JSR WAVE_LOGIC
  JSR UPDATE_HUD
  JSR BUILD_SAT
  JSR VDP_INT_ON
  JMP GAME_LOOP


; the crests of the lava alternate every 16 frames
ANIM_LAVA:
  LDA FRAME_CNT
  AND #$0F
  BNE .al_r
  LDA FRAME_CNT
  LSR A
  LSR A
  LSR A
  LSR A
  STA LAVAPH
  JMP DRAW_LAVA
.al_r:
  RTS

; the lava crests move while the title waits
LAVA_TICK:
  LDA FRAME_CNT
  AND #$0F
  BNE .lt_r
  LDA FRAME_CNT
  LSR A
  LSR A
  LSR A
  LSR A
  STA LAVAPH
  JSR VDP_INT_OFF
  JSR DRAW_LAVA
  JSR VDP_INT_ON
.lt_r:
  RTS


; ===============================================================
;  THE WAVE: type, riders to come, platforms
; ===============================================================
SET_WAVE:
  STZ TEAMHIT
  STZ GLADEND
  STZ WTL
  STZ WTH
  STZ OVERT
  STZ QIDX
  LDA WAVEN                    ; position in the cycle of 5: 0 normal, 1 survival / team,
  SEC                          ;   2 normal / pterodactyl, 3 gladiator, 4 egg
  SBC #1
  LDY #0
.sw_m:
  CMP #5
  BCC .sw_p
  SBC #5
  INY
  BRA .sw_m
.sw_p:
  STA T0                       ; position in the cycle
  STY T6                       ; number of the cycle
  LDA #0
  LDX T0
  BEQ .sw_set                  ; position 0: normal
  CPX #1
  BNE .sw_2
  LDA T6                       ; survival in the even cycles, team in the odd ones (2 players)
  AND #$01
  BEQ .sw_surv
  LDA NPL
  CMP #2
  BCC .sw_surv
  LDA #2
  BRA .sw_set
.sw_surv:
  LDA #1
  BRA .sw_set
.sw_2:
  CPX #2
  BNE .sw_3
  LDA WAVEN
  CMP #8
  LDA #0
  BCC .sw_set
  LDA #5
  BRA .sw_set
.sw_3:
  CPX #3
  BNE .sw_4
  LDA NPL
  CMP #2
  LDA #0
  BCC .sw_set
  LDA #3
  BRA .sw_set
.sw_4:
  LDA #4
.sw_set:
  STA WTYPE
  ; ---- the riders: total = min(3 + (wave + 1) / 3, 8)
  LDA WAVEN
  CLC
  ADC #1
  STA T0
  LDY #0
.sw_t3:
  LDA T0
  CMP #3
  BCC .sw_t3e
  SBC #3
  STA T0
  INY
  BRA .sw_t3
.sw_t3e:
  TYA
  CLC
  ADC #3
  CMP #9
  BCC .sw_tot
  LDA #8
.sw_tot:
  STA T1                       ; total
  LDA #0                       ; shadow lords: (wave - 6) / 3 + 1 from wave 6, at most 4
  STA T2
  LDA WAVEN
  CMP #6
  BCC .sw_sl
  SEC
  SBC #6
  LDY #1
.sw_s3:
  CMP #3
  BCC .sw_s3e
  SBC #3
  INY
  BRA .sw_s3
.sw_s3e:
  TYA
  CMP #5
  BCC .sw_s4
  LDA #4
.sw_s4:
  STA T2
.sw_sl:
  LDA #0                       ; hunters: (wave - 1) / 2 from wave 3
  STA T3
  LDA WAVEN
  CMP #3
  BCC .sw_hn
  SEC
  SBC #1
  LSR A
  STA T3
.sw_hn:
  LDA T2                       ; shadow lords first, then the hunters, the rest bounders
  CMP T1
  BCC .sw_a
  LDA T1
  STA T2
.sw_a:
  LDA T1
  SEC
  SBC T2
  STA T4                       ; left for hunters and bounders
  LDA T3
  CMP T4
  BCC .sw_b
  LDA T4
  STA T3
.sw_b:
  LDA T4
  SEC
  SBC T3
  STA QB
  LDA T3
  STA QH
  LDA T2
  STA QS
  LDA WTYPE
  CMP #4
  BNE .sw_ml
  STZ QB                       ; egg wave: no riders to come, only eggs
  STZ QH
  STZ QS
.sw_ml:
  LDA T1                       ; riders at the same time: 3 + wave / 4, at most the total
  LSR A
  CLC
  ADC #2
  CMP #6
  BCC .sw_mx
  LDA #6
.sw_mx:
  STA MAXLIVE
  RTS


; the platforms of this wave: the full set at waves 1, 2, 5, 6, 7... of the cycle
SET_PLATFORMS:
  LDA WAVEN
  SEC
  SBC #1
.sp_m:
  CMP #5
  BCC .sp_p
  SBC #5
  BRA .sp_m
.sp_p:
  STA T0                       ; position in the cycle
  BNE .sp_nb
  STZ BR_L                     ; back to the start: the bridge is whole again
  STZ BR_R
.sp_nb:
  ASL A
  ASL A
  ASL A
  CLC
  ADC T0                       ; x 9
  TAX
  LDY #$00
.sp_l:
  LDA PF_INIT_ON,X
  STA PF_ON,Y
  LDA PF_X1_T,Y
  STA PF_X1,Y
  LDA PF_X2_T,Y
  STA PF_X2,Y
  LDA PF_Y_T,Y
  STA PF_Y,Y
  INX
  INY
  CPY #NPF
  BNE .sp_l
  JSR BRIDGE_EXTENT
  LDA #75                      ; the first tile burns about 5 seconds after the wave 3 starts
  STA BRN_T
  STZ BR_BT
  RTS

; the two bridges as they are after BR_L / BR_R tiles burnt
BRIDGE_EXTENT:
  LDA BR_L
  ASL A
  ASL A
  ASL A
  STA PF_X1+1
  LDA BR_L
  CMP #9
  BCC .be_r
  STZ PF_ON+1
.be_r:
  LDA BR_R
  ASL A
  ASL A
  ASL A
  STA T0
  LDA #255
  SEC
  SBC T0
  STA PF_X2+2
  LDA BR_R
  CMP #9
  BCC .be_e
  STZ PF_ON+2
.be_e:
  RTS

; everything but the players
CLEAR_OBJECTS:
  LDX #(NC-1)
.co_c:
  CPX #2
  BCC .co_s
  STZ C_ST,X
.co_s:
  DEX
  BPL .co_c
  LDX #(NEG-1)
.co_e:
  STZ E_ST,X
  DEX
  BPL .co_e
  LDX #(NFX-1)
.co_f:
  STZ FX_T,X
  DEX
  BPL .co_f
  STZ PT_ST
  STZ TR_ST
  STZ TR_CD
  STZ NALIVE
  STZ NEGGS
  STZ BANNER
  RTS

; platforms, lava and the HUD
DRAW_FIELD:
  LDX #$00
.df_l:
  LDA PF_ON,X
  BEQ .df_n
  PHX
  TXA
  JSR DRAW_PF
  PLX
.df_n:
  INX
  CPX #NPF
  BNE .df_l
  JSR DRAW_LAVA
  JSR DRAW_LAVA_DEEP
  JSR DRAW_TOP
  JMP DRAW_WAVE

; players that still have riders: they come on the ground
PLACE_PLAYERS:
  LDX #$01
.pp_l:
  LDA LIVES,X
  BNE .pp_a
  STZ C_ST,X
  BRA .pp_n
.pp_a:
  STZ DIED,X
  LDA PL_START_X,X
  STA C_XH,X
  STZ C_XL,X
  LDA #160
  STA C_YH,X
  STZ C_YL,X
  STZ C_VXL,X
  STZ C_VXH,X
  STZ C_VYL,X
  STZ C_VYH,X
  LDA PL_START_F,X
  STA C_FACE,X
  LDA #1
  STA C_GND,X
  STA C_ST,X
  STZ C_TY,X
  STZ C_DIR,X
  STZ C_FLT,X
  STZ C_EGG,X
  STZ C_ANIM,X
  LDA #SAFE_T
  STA C_T,X
  STZ P_OLD,X
.pp_n:
  DEX
  BPL .pp_l
  RTS


; ===============================================================
;  BANNERS
; ===============================================================
SHOW_BANNER:
  LDX WTYPE
  LDA BAN_LO,X
  STA TP
  LDA BAN_HI,X
  STA TP+1
  JSR PRINT
  LDA #1
  STA BANNER
  RTS

HIDE_BANNER:
  LDX #10
  LDY #0
  JSR NT_XY
  LDX #32
  LDA #$00
.hb_l:
  STA VDATA
  DEX
  BNE .hb_l
  LDX #11
  LDY #0
  JSR NT_XY
  LDX #32
  LDA #$00
.hb_m:
  STA VDATA
  DEX
  BNE .hb_m
  STZ BANNER
  RTS


; ===============================================================
;  WAVE LOGIC: counters, spawning, end of the wave, game over
; ===============================================================
WAVE_LOGIC:
  LDA WSTATE
  BNE .wl_run
  LDA MSGT                     ; banner: the riders wait
  BEQ .wl_go
  DEC MSGT
  RTS
.wl_go:
  JSR HIDE_BANNER
  LDA #1
  STA WSTATE
  RTS
.wl_run:
  CMP #2
  BEQ .wl_over
  ; ---- counts
  STZ NALIVE
  LDX #(NC-1)
.wl_c:
  CPX #2
  BCC .wl_cn
  LDA C_ST,X
  BEQ .wl_cn
  INC NALIVE
.wl_cn:
  DEX
  BPL .wl_c
  STZ NEGGS
  LDX #(NEG-1)
.wl_e:
  LDA E_ST,X
  BEQ .wl_en
  INC NEGGS
.wl_en:
  DEX
  BPL .wl_e
  ; ---- time in the wave
  INC WTL
  BNE .wl_t
  INC WTH
.wl_t:
  JSR SPAWN_RIDERS
  JSR CHECK_PTERO_TIME
  ; ---- game over?
  LDA C_ST
  ORA C_ST+1
  BNE .wl_alive
  LDA LIVES
  ORA LIVES+1
  BNE .wl_alive
  JMP GAME_OVER
.wl_alive:
  ; ---- the wave is over when nothing is left
  LDA NALIVE
  ORA NEGGS
  ORA QB
  ORA QH
  ORA QS
  ORA PT_ST
  BNE .wl_r
  LDA #2
  STA WSTATE
  LDA #150
  STA OVERT
  JSR WAVE_BONUS
.wl_r:
  RTS
.wl_over:
  LDA OVERT
  BEQ .wl_next
  DEC OVERT
  RTS
.wl_next:
  JSR HIDE_BANNER
  INC WAVEN
  LDA WAVEN
  CMP #100
  BCC .wl_nw
  LDA #99
  STA WAVEN
.wl_nw:
  JMP WAVE_START


; the bonuses of the special waves
WAVE_BONUS:
  LDA WTYPE
  CMP #1
  BEQ .wb_surv
  CMP #2
  BEQ .wb_team
  RTS
.wb_surv:                      ; survival: 3000 to every player who did not lose a rider
  LDX #$01
.wb_sl:
  LDA C_ST,X
  BEQ .wb_sn
  LDA DIED,X
  BNE .wb_sn
  JSR BONUS_3000
.wb_sn:
  DEX
  BPL .wb_sl
  JMP BONUS_MSG
.wb_team:                      ; team: 3000 each if nobody hit the other
  LDA TEAMHIT
  BNE .wb_no
  LDX #$01
.wb_tl:
  LDA C_ST,X
  BEQ .wb_tn
  JSR BONUS_3000
.wb_tn:
  DEX
  BPL .wb_tl
  JMP BONUS_MSG
.wb_no:
  RTS

BONUS_3000:                    ; X = player (keeps X)
  PHX
  LDA #$00
  STA PTS_L
  LDA #$30
  STA PTS_M
  JSR ADD_SCORE
  PLX
  RTS

BONUS_MSG:
  LDA #<TXT_BONUS
  STA TP
  LDA #>TXT_BONUS
  STA TP+1
  JSR PRINT
  LDA #1
  STA BANNER
  LDA #W_BONUS
  LDX #2
  JMP SFX_WHISTLE


; ===============================================================
;  GAME OVER
; ===============================================================
GAME_OVER:
  JSR HIDE_BANNER
  LDA #<TXT_OVER
  STA TP
  LDA #>TXT_OVER
  STA TP+1
  JSR PRINT
  LDX #$00                     ; the best score
.go_h:
  LDA SCH,X
  CMP HISC+2
  BCC .go_n
  BNE .go_set
  LDA SCM,X
  CMP HISC+1
  BCC .go_n
  BNE .go_set
  LDA SCL,X
  CMP HISC
  BCC .go_n
  BEQ .go_n
.go_set:
  LDA SCL,X
  STA HISC
  LDA SCM,X
  STA HISC+1
  LDA SCH,X
  STA HISC+2
.go_n:
  INX
  CPX #$02
  BNE .go_h
  JSR BUILD_SAT
  JSR VDP_INT_ON
  LDA #200
  JSR WAIT_FRAMES
  JMP TITLE


; ===============================================================
;  SCORE
; ===============================================================
; PTS_L / PTS_M (BCD) to player X; an extra rider every 20000 points (keeps X)
ADD_SCORE:
  PHX
  PHY
  SED
  CLC
  LDA SCL,X
  ADC PTS_L
  STA SCL,X
  LDA SCM,X
  ADC PTS_M
  STA SCM,X
  LDA SCH,X
  ADC #$00
  STA SCH,X
  CLD
  LDA SCH,X
  CMP NXL,X
  BCC .as_d
  SED
  CLC
  LDA NXL,X
  ADC #$02
  STA NXL,X
  CLD
  LDA LIVES,X
  CMP #9
  BCS .as_d
  INC LIVES,X
  PHX
  LDA #W_EXTRA
  LDX #2
  JSR SFX_WHISTLE
  PLX
.as_d:
  LDA SCDIRTY
  ORA BITS,X
  STA SCDIRTY
  PLY
  PLX
  RTS

; the scores and the riders changed in this frame are drawn again
UPDATE_HUD:
  LDA SCDIRTY
  BEQ .uh_r
  STZ SCDIRTY
  LDX #$00
  JSR DRAW_SCORE
  JSR DRAW_LIVES
  LDX #$01
  JSR DRAW_SCORE
  JSR DRAW_LIVES
.uh_r:
  RTS



; ===============================================================
;  PLAYERS: joystick, physics, dying and coming back
; ===============================================================
UPDATE_PLAYERS:
  LDX #$00
.up_l:
  STX CI
  LDA C_ST,X
  CMP #1
  BEQ .up_alive
  CMP #2
  BEQ .up_dying
  CMP #3
  BEQ .up_coming
  BRA .up_n
.up_alive:
  JSR PLAYER_CTRL
  JSR CR_UPDATE
  LDX CI
  LDA C_ST,X                   ; still flying: the safe time runs out
  CMP #1
  BNE .up_n
  LDA C_T,X
  BEQ .up_n
  DEC C_T,X
  BRA .up_n
.up_dying:
  JSR DYING_TICK
  BRA .up_n
.up_coming:
  JSR COMING_TICK
.up_n:
  LDX CI
  INX
  CPX #2
  BNE .up_l
  RTS

; X = player: C_DIR and FLAPQ from his joystick
PLAYER_CTRL:
  LDA NPL
  CMP #2
  BEQ .pc_two
  LDA P_JOY                    ; one player: both joysticks drive him
  ORA P_JOY+1
  BRA .pc_got
.pc_two:
  LDA P_JOY,X
.pc_got:
  STA T0
  STZ C_DIR,X
  AND #%00001000
  BEQ .pc_nr
  LDA #1
  STA C_DIR,X
.pc_nr:
  LDA T0
  AND #%00000100
  BEQ .pc_nl
  LDA C_DIR,X
  BNE .pc_both
  LDA #2
  STA C_DIR,X
  BRA .pc_nl
.pc_both:
  STZ C_DIR,X                  ; left and right together: neither
.pc_nl:
  LDA T0
  AND #BTN_MASK
  STA T1
  LDA P_OLD,X
  EOR #$FF
  AND T1                       ; a button pressed now and not before: flap
  STA FLAPQ
  LDA T1
  STA P_OLD,X
  RTS

; X = player dying: then he comes back, or he is out
DYING_TICK:
  DEC C_T,X
  BNE .dt_r
  LDA LIVES,X
  BEQ .dt_out
  LDA #3
  STA C_ST,X
  LDA #45
  STA C_T,X
  LDA PL_START_X,X
  STA C_XH,X
  STZ C_XL,X
  LDA #160
  STA C_YH,X
  STZ C_YL,X
  STZ C_VXL,X
  STZ C_VXH,X
  STZ C_VYL,X
  STZ C_VYH,X
  STZ C_FLT,X
  LDA PL_START_F,X
  STA C_FACE,X
  LDA #W_SPAWN
  JMP SFX_WHISTLE
.dt_out:
  STZ C_ST,X
.dt_r:
  RTS

; X = creature in the sparkle: then it flies
COMING_TICK:
  DEC C_T,X
  BNE .ct_r
  LDA #1
  STA C_ST,X
  LDA C_TY,X
  BNE .ct_en
  LDA #SAFE_T                  ; a player: safe for a while
  STA C_T,X
  STZ P_OLD,X
  RTS
.ct_en:
  STZ C_T,X
  LDA #1
  STA C_AT,X
.ct_r:
  RTS


; ===============================================================
;  PHYSICS of a creature: X = slot, C_DIR and FLAPQ set (keeps X)
; ===============================================================
CR_UPDATE:
  LDY C_TY,X
  LDA C_DIR,X
  BNE .cu_dir
  JMP .cu_fric
.cu_dir:
  CMP #1
  BNE .cu_left
  STZ C_FACE,X                 ; ---- right: faster up to the top speed of its kind
  CLC
  LDA C_VXL,X
  ADC ACC_T,Y
  STA C_VXL,X
  LDA C_VXH,X
  ADC #0
  STA C_VXH,X
  SEC
  LDA C_VXL,X
  SBC VMX_L,Y
  LDA C_VXH,X
  SBC VMX_H,Y
  BPL .cu_rcl
  JMP .cu_hx
.cu_rcl:
  LDA VMX_L,Y
  STA C_VXL,X
  LDA VMX_H,Y
  STA C_VXH,X
  JMP .cu_hx
.cu_left:
  LDA #1                       ; ---- left
  STA C_FACE,X
  SEC
  LDA C_VXL,X
  SBC ACC_T,Y
  STA C_VXL,X
  LDA C_VXH,X
  SBC #0
  STA C_VXH,X
  CLC
  LDA C_VXL,X
  ADC VMX_L,Y
  LDA C_VXH,X
  ADC VMX_H,Y
  BPL .cu_hx
  SEC
  LDA #0
  SBC VMX_L,Y
  STA C_VXL,X
  LDA #0
  SBC VMX_H,Y
  STA C_VXH,X
  BRA .cu_hx
.cu_fric:                      ; ---- no direction: it slows down (much more on a platform)
  LDA #FR_AIR
  LDY C_GND,X
  BEQ .cf_a
  LDA #FR_GND
.cf_a:
  STA T0
  LDA C_VXH,X
  BMI .cf_neg
  SEC
  LDA C_VXL,X
  SBC T0
  STA C_VXL,X
  LDA C_VXH,X
  SBC #0
  STA C_VXH,X
  BPL .cu_hx
  STZ C_VXL,X
  STZ C_VXH,X
  BRA .cu_hx
.cf_neg:
  CLC
  LDA C_VXL,X
  ADC T0
  STA C_VXL,X
  LDA C_VXH,X
  ADC #0
  STA C_VXH,X
  BMI .cu_hx
  STZ C_VXL,X
  STZ C_VXH,X
.cu_hx:
  LDA FLAPQ                    ; ---- a flap pushes up
  BEQ .cu_nf
  STZ FLAPQ
  SEC
  LDA C_VYL,X
  SBC #<FLAP_V
  STA C_VYL,X
  LDA C_VYH,X
  SBC #>FLAP_V
  STA C_VYH,X
  CLC
  LDA C_VYL,X
  ADC #<VUP_MAX
  LDA C_VYH,X
  ADC #>VUP_MAX
  BPL .cu_fu
  LDA #<VUP_NEG
  STA C_VYL,X
  LDA #>VUP_NEG
  STA C_VYH,X
.cu_fu:
  LDA #FLAP_ANIM
  STA C_FLT,X
  LDA C_TY,X
  BNE .cu_nf
  LDA #W_FLAP                  ; the player's flap, on his side
  JSR SFX_WHISTLE
.cu_nf:
  CLC                          ; ---- gravity
  LDA C_VYL,X
  ADC #<GRAV
  STA C_VYL,X
  LDA C_VYH,X
  ADC #>GRAV
  STA C_VYH,X
  SEC
  LDA C_VYL,X
  SBC #<VDN_MAX
  LDA C_VYH,X
  SBC #>VDN_MAX
  BMI .cu_gv
  LDA #<VDN_MAX
  STA C_VYL,X
  LDA #>VDN_MAX
  STA C_VYH,X
.cu_gv:
  LDA C_YH,X                   ; ---- move
  STA PQO
  CLC
  LDA C_XL,X
  ADC C_VXL,X
  STA C_XL,X
  LDA C_XH,X
  ADC C_VXH,X
  STA C_XH,X
  CLC
  LDA C_YL,X
  ADC C_VYL,X
  STA C_YL,X
  LDA C_YH,X
  ADC C_VYH,X
  STA C_YH,X
  CMP #CEIL_Y                  ; ---- the ceiling
  BCS .cu_nc
  LDA #CEIL_Y
  STA C_YH,X
  STZ C_YL,X
  LDA C_VYH,X
  BPL .cu_nc
  LDA #$60
  STA C_VYL,X
  STZ C_VYH,X
.cu_nc:
  LDA C_XH,X                   ; ---- platforms
  STA PQX
  LDA C_YH,X
  STA PQY
  LDA C_VYH,X
  STA PQV
  LDA #HWC
  STA PQW
  LDA #HHC
  STA PQH
  JSR PLAT_COLL
  STZ C_GND,X
  LDA PQR
  LSR A
  BCC .cu_nl
  LDA PQY                      ; landed
  STA C_YH,X
  STZ C_YL,X
  STZ C_VYL,X
  STZ C_VYH,X
  LDA #1
  STA C_GND,X
  BRA .cu_side
.cu_nl:
  LSR A
  BCC .cu_side
  LDA PQY                      ; head against a platform: down again
  STA C_YH,X
  STZ C_YL,X
  LDA #$40
  STA C_VYL,X
  STZ C_VYH,X
.cu_side:
  LDA PQR
  AND #%00001100
  BEQ .cu_ns
  LDA PQX                      ; against the side of a platform: back at half speed
  STA C_XH,X
  STZ C_XL,X
  SEC
  LDA #0
  SBC C_VXL,X
  STA C_VXL,X
  LDA #0
  SBC C_VXH,X
  STA C_VXH,X
  CMP #$80
  ROR C_VXH,X
  ROR C_VXL,X
.cu_ns:
  LDA C_FLT,X                  ; ---- wings and steps
  BEQ .cu_w
  DEC C_FLT,X
.cu_w:
  LDA C_GND,X
  BEQ .cu_lava
  LDA C_VXL,X
  ORA C_VXH,X
  BEQ .cu_lava
  INC C_ANIM,X
  LDA C_TY,X
  BNE .cu_lava
  LDA C_ANIM,X
  AND #$07
  BNE .cu_lava
  LDA #W_STEP
  JSR SFX_WHISTLE
.cu_lava:
  LDA C_YH,X                   ; ---- the lava
  CMP #LAVA_CY
  BCC .cu_r
  JMP LAVA_DEATH
.cu_r:
  RTS


; ===============================================================
;  PLATFORMS: PQX, PQY (new centre), PQO (old Y), PQV (sign of the
;  vertical speed), PQW / PQH (half sizes) -> PQR bit 0 landed,
;  bit 1 head hit, bit 2 pushed left, bit 3 pushed right;
;  PQX / PQY corrected (keeps X)
; ===============================================================
PLAT_COLL:
  STZ PQR
  JSR PQ_EDGES
  LDY #(NPF-1)
.pl_l:
  LDA PF_ON,Y
  BEQ .pl_skip
  LDA T0                       ; ---- the feet above its top: nothing
  CMP PF_Y,Y
  BCC .pl_skip
  LDA PF_Y,Y
  STA T4
  CLC
  ADC #8
  STA T3
  LDA T2                       ; the head under its bottom: nothing
  CMP T3
  BCS .pl_skip
  LDA PQX                      ; ---- across it?
  CLC
  ADC PQW
  BCS .pl_a
  CMP PF_X1,Y
  BCC .pl_skip
  BEQ .pl_skip
.pl_a:
  LDA PQX
  SEC
  SBC PQW
  BCC .pl_b
  CMP PF_X2,Y
  BEQ .pl_b
  BCC .pl_b
.pl_skip:
  JMP .pl_n
.pl_b:
  LDA PQV
  BMI .pl_up
  LDA T4                       ; going down: the feet were above the top and now they are not
  CMP T1
  BCC .pl_side
  LDA T4
  SEC
  SBC PQH
  STA PQY
  LDA PQR
  ORA #1
  STA PQR
  JSR PQ_EDGES
  BRA .pl_n
.pl_up:
  LDA T5                       ; going up: the head was below the bottom and now it is not
  CMP T3
  BCC .pl_side
  LDA T3
  CLC
  ADC PQH
  STA PQY
  LDA PQR
  ORA #2
  STA PQR
  JSR PQ_EDGES
  BRA .pl_n
.pl_side:
  LDA T0                       ; inside it: out by the nearer side
  CMP T4
  BEQ .pl_n
  LDA PF_X1,Y
  BEQ .pl_pr                   ; it touches the left edge: out on the right
  LDA PF_X2,Y
  CMP #255
  BEQ .pl_pl                   ; it touches the right edge: out on the left
  LDA PF_X1,Y
  CLC
  ADC PF_X2,Y
  ROR A
  CMP PQX
  BCS .pl_pl
.pl_pr:
  LDA PF_X2,Y
  SEC
  ADC PQW
  STA PQX
  LDA PQR
  ORA #8
  STA PQR
  BRA .pl_n
.pl_pl:
  LDA PF_X1,Y
  CLC
  SBC PQW
  STA PQX
  LDA PQR
  ORA #4
  STA PQR
.pl_n:
  DEY
  BMI .pl_r
  JMP .pl_l
.pl_r:
  RTS

; T0 = feet, T1 = old feet, T2 = head, T5 = old head
PQ_EDGES:
  LDA PQY
  CLC
  ADC PQH
  STA T0
  LDA PQY
  SEC
  SBC PQH
  STA T2
  LDA PQO
  CLC
  ADC PQH
  STA T1
  LDA PQO
  SEC
  SBC PQH
  STA T5
  RTS


; ===============================================================
;  DEATHS
; ===============================================================
; X = creature in the lava
LAVA_DEATH:
  LDA C_XH,X
  STA T0
  LDA C_YH,X
  STA T1
  LDA #0
  JSR NEW_FX
  LDA #S_LAVA
  LDY C_XH,X
  PHX
  JSR BOOM_AT
  PLX
  LDA C_TY,X
  BEQ .ld_pl
  STZ C_ST,X
  RTS
.ld_pl:
  LDA #$FF
  STA KILLER
  ; fall into KILL_PLAYER

; X = player unseated or burnt; KILLER = the other player or $FF (keeps X)
KILL_PLAYER:
  LDA #2
  STA C_ST,X
  LDA #50
  STA C_T,X
  STZ C_VXL,X
  STZ C_VXH,X
  STZ C_VYL,X
  STZ C_VYH,X
  STZ C_DIR,X
  LDA #1
  STA DIED,X
  STZ CHAIN,X                  ; the row of the eggs starts again
  LDA LIVES,X
  BEQ .kp_l
  DEC LIVES,X
.kp_l:
  LDA SCDIRTY
  ORA BITS,X
  STA SCDIRTY
  LDA #W_DIE
  JSR SFX_WHISTLE
  LDA TR_ST                    ; the troll lets go
  BEQ .kp_r
  TXA
  CMP TR_C
  BNE .kp_r
  LDA #3
  STA TR_ST
  STZ TR_T
.kp_r:
  RTS

; X = rider unseated by player KILLER: points, egg, explosion (keeps X)
KILL_ENEMY:
  LDY C_TY,X
  LDA TY_PL,Y
  STA PTS_L
  LDA TY_PM,Y
  STA PTS_M
  PHX
  LDX KILLER
  JSR ADD_SCORE
  LDA #W_JOUST
  JSR SFX_WHISTLE
  PLX
  LDA C_ST,X
  CMP #4
  BNE .ke_egg
  LDY C_EGG,X                  ; a buzzard coming for its rider: the egg waits again
  DEY
  LDA #2
  STA E_ST,Y
  LDA #20
  STA E_T,Y
  LDA #0
  STA E_PEN,Y
  BRA .ke_fx
.ke_egg:
  JSR SPAWN_EGG
.ke_fx:
  LDA C_XH,X
  STA T0
  LDA C_YH,X
  STA T1
  LDA #0
  JSR NEW_FX
  STZ C_ST,X
  LDA TR_ST                    ; the troll lets go
  BEQ .ke_r
  TXA
  CMP TR_C
  BNE .ke_r
  LDA #3
  STA TR_ST
  STZ TR_T
.ke_r:
  RTS


; ===============================================================
;  JOUSTS: every pair of creatures that touch
; ===============================================================
COLLIDE:
  LDX #$00
.co_i:
  STX CI
  LDA C_ST,X
  CMP #1
  BEQ .co_ok
  CMP #4
  BNE .co_ni
.co_ok:
  TXA
  TAY
.co_j:
  INY
  CPY #NC
  BCS .co_ni
  STY CJ
  LDA C_ST,Y
  CMP #1
  BEQ .co_ok2
  CMP #4
  BNE .co_j
.co_ok2:
  LDA C_XH,X                   ; |dx| < 12 (the field wraps)
  SEC
  SBC C_XH,Y
  STA DXV
  BPL .co_dx
  EOR #$FF
  CLC
  ADC #1
.co_dx:
  CMP #12
  BCS .co_j
  LDA C_YH,X                   ; |dy| < 13
  SEC
  SBC C_YH,Y
  STA DYV
  BPL .co_dy
  EOR #$FF
  CLC
  ADC #1
.co_dy:
  CMP #13
  BCS .co_j
  JSR JOUST_PAIR
  LDX CI
  LDY CJ
  LDA C_ST,X                   ; the first one may be gone
  CMP #1
  BEQ .co_j
  CMP #4
  BEQ .co_j
.co_ni:
  LDX CI                       ; only pairs with a player (the riders of the computer pass each other)
  INX
  CPX #2
  BCC .co_i
  RTS

; X, Y = the two creatures; DXV = x(X) - x(Y), DYV = y(X) - y(Y)
JOUST_PAIR:
  LDA C_TY,X
  BEQ .jp_go
  LDA C_TY,Y
  BEQ .jp_go
  JMP BOUNCE                   ; two riders of the computer: they bounce
.jp_go:
  LDA C_TY,X                   ; two players in the team wave: the bonus is lost
  ORA C_TY,Y
  BNE .jp_h
  LDA WTYPE
  CMP #2
  BNE .jp_h
  LDA #1
  STA TEAMHIT
.jp_h:
  LDA DYV                      ; who is higher? (at least 4 pixels)
  CLC
  ADC #3
  BMI .jp_xwin
  LDA DYV
  SEC
  SBC #4
  BPL .jp_ywin
  JMP BOUNCE
.jp_xwin:                      ; X wins, Y loses
  STX WINNER
  TYA
  TAX
  LDY WINNER
  BRA .jp_res
.jp_ywin:                      ; Y wins, X loses
  STY WINNER
.jp_res:                       ; now X = loser, WINNER = winner
  LDA C_TY,X
  BNE .jp_rider
  LDA C_T,X                    ; a player still safe: they bounce
  BEQ .jp_pl
  LDY WINNER
  JMP BOUNCE
.jp_pl:
  LDY WINNER
  LDA C_TY,Y
  BNE .jp_byr
  STY KILLER                   ; unseated by the other player: 50, or 3000 in the gladiator wave
  JSR KILL_PLAYER
  LDA #$50
  STA PTS_L
  STZ PTS_M
  LDA WTYPE
  CMP #3
  BNE .jp_50
  LDA GLADEND
  BNE .jp_50
  LDA #1
  STA GLADEND
  STZ PTS_L
  LDA #$30
  STA PTS_M
.jp_50:
  LDX KILLER
  JSR ADD_SCORE
  LDA #W_JOUST
  JMP SFX_WHISTLE
.jp_byr:
  LDA #$FF
  STA KILLER
  JMP KILL_PLAYER
.jp_rider:
  LDY WINNER                   ; the loser is a rider: the winner is a player
  STY KILLER
  JMP KILL_ENEMY

; X, Y bounce: they swap the horizontal speeds and move apart
BOUNCE:
  LDA C_VXL,X
  PHA
  LDA C_VXL,Y
  STA C_VXL,X
  PLA
  STA C_VXL,Y
  LDA C_VXH,X
  PHA
  LDA C_VXH,Y
  STA C_VXH,X
  PLA
  STA C_VXH,Y
  LDA C_XH,X
  SEC
  SBC C_XH,Y
  BMI .bo_n
  INC C_XH,X
  INC C_XH,X
  LDA C_XH,Y
  SEC
  SBC #2
  STA C_XH,Y
  RTS
.bo_n:
  DEC C_XH,X
  DEC C_XH,X
  LDA C_XH,Y
  CLC
  ADC #2
  STA C_XH,Y
  RTS


; ===============================================================
;  RIDERS OF THE COMPUTER
; ===============================================================
UPDATE_ENEMIES:
  LDX #2
.ue_l:
  STX CI
  LDA C_ST,X
  BEQ .ue_n
  CMP #3
  BNE .ue_a
  JSR COMING_TICK
  BRA .ue_n
.ue_a:
  CMP #5
  BEQ .ue_n                    ; held by the troll
  JSR ENEMY_AI
  LDX CI
  JSR CR_UPDATE
.ue_n:
  LDX CI
  INX
  CPX #NC
  BNE .ue_l
  RTS

; X = rider: direction (C_DIR) and flap (FLAPQ)
ENEMY_AI:
  LDA C_ST,X
  CMP #4
  BNE .ea_n
  JSR FETCH_AI
  BRA .ea_fl
.ea_n:
  DEC C_AT,X
  BNE .ea_fl
  JSR AI_THINK
.ea_fl:
  LDA C_T,X                    ; frames between two flaps
  BEQ .ea_c
  DEC C_T,X
  RTS
.ea_c:
  LDA C_YH,X
  CMP #140                     ; low over the lava: up!
  BCS .ea_flap
  CMP C_TGY,X
  BCC .ea_r                    ; higher than it wants
  BEQ .ea_r
  LDA C_VYH,X
  BPL .ea_ok
  CMP #$FF
  BCC .ea_r                    ; already going up fast
.ea_ok:
  LDA RND
  EOR C_AT,X
  AND #$03
  BEQ .ea_r
.ea_flap:
  LDA #1
  STA FLAPQ
  LDY C_TY,X
  LDA FLAP_CD,Y
  STA C_T,X
.ea_r:
  RTS

; X = rider: a new plan (direction, height, time before the next one)
AI_THINK:
  JSR NEAREST_PLAYER
  LDA C_TY,X
  CMP #1
  BEQ .at_wander               ; bounders wander
  LDA NEAR
  BMI .at_wander
  LDA NDX                      ; hunters and shadow lords go for the nearest player
  JSR DIR_TO
  LDA NDY
  LDY C_TY,X
  CPY #3
  BNE .at_h
  SEC                          ; a shadow lord wants to be above him
  SBC #22
  BCS .at_hc
  LDA #(CEIL_Y+6)
.at_hc:
  CMP #(CEIL_Y+6)
  BCS .at_h
  LDA #(CEIL_Y+6)
.at_h:
  STA C_TGY,X
  LDA RND
  AND #$0F
  CLC
  ADC AI_T,Y
  STA C_AT,X
  RTS
.at_wander:
  LDA RND
  AND #$01
  CLC
  ADC #1
  STA C_DIR,X
  LDA RND
  LSR A
  AND #$3F
  CLC
  ADC #50
  STA C_TGY,X
  LDA RND
  AND #$1F
  CLC
  ADC #40
  STA C_AT,X
  RTS

; A = signed distance: C_DIR of X towards it (none when closer than 6)
DIR_TO:
  STA T5
  BPL .di_p
  EOR #$FF
  CLC
  ADC #1
.di_p:
  CMP #6
  BCS .di_go
  STZ C_DIR,X
  RTS
.di_go:
  LDA T5
  BMI .di_l
  LDA #1
  STA C_DIR,X
  RTS
.di_l:
  LDA #2
  STA C_DIR,X
  RTS

; X = rider: NEAR = nearest player flying ($FF = none), NDX = his X - mine (signed), NDY = his Y
NEAREST_PLAYER:
  LDA #$FF
  STA NEAR
  STA T6
  LDY #1
.np_l:
  LDA C_ST,Y
  CMP #1
  BNE .np_n
  LDA C_XH,Y
  SEC
  SBC C_XH,X
  STA T5
  BPL .np_p
  EOR #$FF
  CLC
  ADC #1
.np_p:
  CMP T6
  BCS .np_n
  STA T6
  STY NEAR
  LDA T5
  STA NDX
  LDA C_YH,Y
  STA NDY
.np_n:
  DEY
  BPL .np_l
  RTS

; X = buzzard coming for its rider: to the egg, and it takes him
FETCH_AI:
  LDY C_EGG,X
  DEY
  LDA E_YH,Y
  SEC
  SBC #6
  STA C_TGY,X
  LDA E_XH,Y
  SEC
  SBC C_XH,X
  STA T4
  BPL .fa_p
  EOR #$FF
  CLC
  ADC #1
.fa_p:
  CMP #7
  BCS .fa_dir
  LDA E_YH,Y                   ; over the egg: is it low enough?
  SEC
  SBC C_YH,X
  BPL .fa_q
  EOR #$FF
  CLC
  ADC #1
.fa_q:
  CMP #14
  BCS .fa_stop
  LDA #0                       ; the rider is back on his buzzard
  STA E_ST,Y
  STA E_PEN,Y
  STZ C_EGG,X
  LDA #1
  STA C_ST,X
.fa_stop:
  STZ C_DIR,X
  RTS
.fa_dir:
  LDA T4
  JMP DIR_TO


; ===============================================================
;  NEW RIDERS: one at a time from the spawn points
; ===============================================================
SPAWN_RIDERS:
  LDA QB
  ORA QH
  ORA QS
  BEQ .sr_r
  LDA QSPAWN
  BEQ .sr_try
  DEC QSPAWN
.sr_r:
  RTS
.sr_try:
  LDA NALIVE
  CMP MAXLIVE
  BCS .sr_r
  LDX #2
.sr_f:
  LDA C_ST,X
  BEQ .sr_got
  INX
  CPX #NC
  BCC .sr_f
  RTS
.sr_got:
  STX CJ
  JSR PICK_TYPE
  BEQ .sr_r
  LDX CJ
  STA C_TY,X
  JSR PICK_PAD
  LDX CJ
  JSR PUT_RIDER
  LDA WAVEN                    ; the next one: 80 - 2 x wave frames, at least 30
  ASL A
  STA T0
  LDA #80
  SEC
  SBC T0
  BCC .sr_m
  CMP #30
  BCS .sr_t
.sr_m:
  LDA #30
.sr_t:
  STA QSPAWN
  INC NALIVE
  LDA #W_SPAWN
  LDX #2
  JMP SFX_WHISTLE

; A = kind of the next rider (1 bounder, 2 hunter, 3 shadow lord), 0 = none; uses X
PICK_TYPE:
  LDX QIDX
  LDY #3
.pt_l:
  LDA QB,X
  BNE .pt_f
  INX
  CPX #3
  BCC .pt_n
  LDX #0
.pt_n:
  DEY
  BNE .pt_l
  LDA #0
  RTS
.pt_f:
  STX T0
  DEC QB,X
  INX
  CPX #3
  BCC .pt_s
  LDX #0
.pt_s:
  STX QIDX
  LDA T0
  CLC
  ADC #1
  RTS

; T0 / T1 = a spawn point on a platform that is there
PICK_PAD:
  LDA #8
  STA TRY
.pk_l:
  JSR NEXT_RND
  AND #$07
  CMP #5
  BCS .pk_n
  TAY
  LDX PAD_PF,Y
  LDA PF_ON,X
  BEQ .pk_n
  BRA .pk_s
.pk_n:
  DEC TRY
  BNE .pk_l
  LDY #4                       ; the ground is always there
.pk_s:
  LDA PAD_X,Y
  STA T0
  LDA PAD_Y,Y
  STA T1
  RTS

; X = slot: a rider appears at T0 / T1 (sparkle first)
PUT_RIDER:
  LDA T0
  STA C_XH,X
  LDA T1
  STA C_YH,X
  STZ C_XL,X
  STZ C_YL,X
  STZ C_VXL,X
  STZ C_VXH,X
  STZ C_VYL,X
  STZ C_VYH,X
  STZ C_GND,X
  STZ C_DIR,X
  STZ C_FLT,X
  STZ C_EGG,X
  STZ C_ANIM,X
  LDA #3
  STA C_ST,X
  LDA #40
  STA C_T,X
  LDA RND
  AND #$01
  STA C_FACE,X
  LDA #80
  STA C_TGY,X
  LDA #1
  STA C_AT,X
  RTS


; ===============================================================
;  EGGS
; ===============================================================
; A = time before an egg hatches (units of 4 frames): 70 - 2 x wave, at least 30
HATCH_TIME:
  LDA WAVEN
  ASL A
  STA SMT1
  LDA #70
  SEC
  SBC SMT1
  BCC .ht_m
  CMP #30
  BCS .ht_r
.ht_m:
  LDA #30
.ht_r:
  RTS

; X = rider unseated: his egg falls from there (keeps X)
SPAWN_EGG:
  LDY #(NEG-1)
.se_l:
  LDA E_ST,Y
  BEQ .se_f
  DEY
  BPL .se_l
  RTS
.se_f:
  LDA #30
  STA E_GR,Y
  LDA #1
  STA E_ST,Y
  LDA C_XH,X
  STA E_XH,Y
  LDA C_YH,X
  STA E_YH,Y
  LDA #0
  STA E_XL,Y
  STA E_YL,Y
  STA E_VYL,Y
  STA E_PEN,Y
  LDA #$FF                     ; it jumps up a little
  STA E_VYH,Y
  LDA C_VXH,X                  ; half the speed of the rider
  CMP #$80
  ROR A
  STA E_VXH,Y
  LDA C_VXL,X
  ROR A
  STA E_VXL,Y
  LDA C_TY,X
  STA E_TY,Y
  PHY
  JSR HATCH_TIME
  PLY
  STA E_T,Y
  RTS

; the egg wave: eggs fall on the platforms
SPAWN_EGGWAVE:
  LDA #6
  LDX WAVEN
  CPX #10
  BCC .ew_n
  LDA #8
.ew_n:
  STA T2
  LDX #0
.ew_l:
  LDA #1
  STA E_ST,X
  LDA EGGW_X,X
  STA E_XH,X
  LDA EGGW_Y,X
  STA E_YH,X
  STZ E_XL,X
  STZ E_YL,X
  STZ E_VXL,X
  STZ E_VXH,X
  STZ E_VYL,X
  STZ E_VYH,X
  STZ E_PEN,X
  STZ E_GR,X
  LDA #1
  LDY WAVEN
  CPY #15
  BCC .ew_t
  LDA #2
.ew_t:
  STA E_TY,X
  JSR HATCH_TIME               ; as long as the eggs of the riders
  STA E_T,X
  INX
  CPX T2
  BNE .ew_l
  RTS

UPDATE_EGGS:
  LDX #(NEG-1)
.ug_l:
  STX CI
  LDA E_ST,X
  BEQ .ug_n
  CMP #3
  BEQ .ug_pk
  CMP #2
  BNE .ug_ph
  TXA                          ; resting: the fall is checked once every 8 frames
  CLC
  ADC FRAME_CNT
  AND #$07
  BNE .ug_pk
.ug_ph:
  JSR EGG_PHYS
  LDX CI
  LDA E_ST,X
  BEQ .ug_n
.ug_pk:
  JSR EGG_PICKUP
  LDX CI
  LDA E_ST,X
  CMP #2
  BNE .ug_n
  JSR EGG_HATCH
.ug_n:
  LDX CI
  DEX
  BPL .ug_l
  RTS

; X = egg: it falls, bounces and stops on a platform
EGG_PHYS:
  CLC
  LDA E_VYL,X
  ADC #$14
  STA E_VYL,X
  LDA E_VYH,X
  ADC #0
  STA E_VYH,X
  BMI .ep_v
  CMP #4
  BCC .ep_v
  LDA #4
  STA E_VYH,X
  STZ E_VYL,X
.ep_v:
  LDA E_YH,X
  STA PQO
  CLC
  LDA E_XL,X
  ADC E_VXL,X
  STA E_XL,X
  LDA E_XH,X
  ADC E_VXH,X
  STA E_XH,X
  CLC
  LDA E_YL,X
  ADC E_VYL,X
  STA E_YL,X
  LDA E_YH,X
  ADC E_VYH,X
  STA E_YH,X
  LDA E_XH,X
  STA PQX
  LDA E_YH,X
  STA PQY
  LDA E_VYH,X
  STA PQV
  LDA #3
  STA PQW
  LDA #4
  STA PQH
  JSR PLAT_COLL
  LDA PQR
  LSR A
  BCC .ep_air
  LDA PQY                      ; on a platform: bounce at half speed, or stop
  STA E_YH,X
  STZ E_YL,X
  LDA E_VYH,X
  LSR A
  STA T0
  LDA E_VYL,X
  ROR A
  STA T1
  LDA T0
  BNE .ep_b
  LDA T1
  CMP #$70
  BCS .ep_b
  STZ E_VYL,X
  STZ E_VYH,X
  STZ E_VXL,X
  STZ E_VXH,X
  LDA #2
  STA E_ST,X
  BRA .ep_s
.ep_b:
  SEC
  LDA #0
  SBC T1
  STA E_VYL,X
  LDA #0
  SBC T0
  STA E_VYH,X
  LDA E_VXH,X
  CMP #$80
  ROR E_VXH,X
  ROR E_VXL,X
  BRA .ep_s
.ep_air:
  LSR A
  BCC .ep_s
  LDA PQY
  STA E_YH,X
  STZ E_VYL,X
  STZ E_VYH,X
.ep_s:
  LDA PQR
  AND #%00001100
  BEQ .ep_l
  LDA PQX
  STA E_XH,X
  SEC
  LDA #0
  SBC E_VXL,X
  STA E_VXL,X
  LDA #0
  SBC E_VXH,X
  STA E_VXH,X
.ep_l:
  LDA E_YH,X                   ; into the lava: gone
  CMP #174
  BCC .ep_r
  STZ E_ST,X
.ep_r:
  RTS

; X = egg: a player that touches it picks it up
EGG_PICKUP:
  LDA E_GR,X                   ; just dropped: it can be seen falling first
  CMP #2
  BCC .ek_go
  DEC E_GR,X
  RTS
.ek_go:
  LDY #1
.ek_l:
  LDA C_ST,Y
  CMP #1
  BNE .ek_n
  LDA C_XH,Y
  SEC
  SBC E_XH,X
  BPL .ek_x
  EOR #$FF
  CLC
  ADC #1
.ek_x:
  CMP #10
  BCS .ek_n
  LDA C_YH,Y
  SEC
  SBC E_YH,X
  BPL .ek_y
  EOR #$FF
  CLC
  ADC #1
.ek_y:
  CMP #13
  BCS .ek_n
  LDA E_GR,X                   ; dropped on a player: he must leave it first
  BNE .ek_r
  JMP EGG_TAKE
.ek_n:
  DEY
  BPL .ek_l
  STZ E_GR,X                   ; nobody on it: it can be picked up
.ek_r:
  RTS

; Y = player, CI = egg: 250, 500, 750, 1000 in a row, +500 in the air
EGG_TAKE:
  STY KILLER
  LDX KILLER
  LDA CHAIN,X
  CMP #3
  BCC .et_c
  LDA #3
.et_c:
  TAY
  LDA EGG_PL,Y
  STA PTS_L
  LDA EGG_PM,Y
  STA PTS_M
  LDA CHAIN,X
  CMP #3
  BCS .et_nc
  INC CHAIN,X
.et_nc:
  LDY CI
  LDA E_ST,Y
  CMP #1
  BNE .et_g
  SED
  CLC
  LDA PTS_M
  ADC #$05
  STA PTS_M
  CLD
  LDA #W_EGGAIR
  BRA .et_s
.et_g:
  LDA #W_EGG
.et_s:
  JSR SFX_WHISTLE
  JSR ADD_SCORE
  LDY CI
  LDA E_XH,Y
  STA T0
  LDA E_YH,Y
  STA T1
  LDA #1
  JSR NEW_FX
  LDY CI
  LDA E_PEN,Y                  ; a buzzard was coming: it stays a rider without the egg
  BEQ .et_e
  TAX
  LDA #1
  STA C_ST,X
  STZ C_EGG,X
.et_e:
  LDY CI
  LDA #0
  STA E_ST,Y
  STA E_PEN,Y
  RTS

; X = egg resting: its clock; then it hatches and a buzzard comes for the rider
EGG_HATCH:
  LDA WSTATE                   ; the clock waits for the end of the banner
  BEQ .eh_r
  LDA FRAME_CNT
  AND #$03
  BNE .eh_r
  DEC E_T,X
  BNE .eh_r
  LDA NALIVE                   ; at most 6 riders on the field
  CMP #6
  BCS .eh_wait
  LDY #2
.eh_f:
  LDA C_ST,Y
  BEQ .eh_got
  INY
  CPY #NC
  BCC .eh_f
.eh_wait:
  LDA #10                      ; no room: a little later
  STA E_T,X
.eh_r:
  RTS
.eh_got:
  INC NALIVE
  LDA #3
  STA E_ST,X
  TYA
  STA E_PEN,X
  LDA E_TY,X                   ; he comes back one kind better
  CMP #3
  BCS .eh_t
  INC A
.eh_t:
  STA C_TY,Y
  TXA
  INC A
  STA C_EGG,Y
  LDA #4
  STA C_ST,Y
  LDA #0
  STA C_XL,Y
  STA C_YL,Y
  STA C_VYL,Y
  STA C_VYH,Y
  STA C_GND,Y
  STA C_DIR,Y
  STA C_FLT,Y
  STA C_ANIM,Y
  STA C_T,Y
  LDA #1
  STA C_AT,Y
  LDA E_YH,X
  SEC
  SBC #24
  STA C_YH,Y
  LDA RND                      ; from one of the two edges
  AND #$01
  BEQ .eh_left
  LDA #250
  STA C_XH,Y
  LDA #1
  STA C_FACE,Y
  LDA #$80
  STA C_VXL,Y
  LDA #$FE
  STA C_VXH,Y
  BRA .eh_snd
.eh_left:
  LDA #6
  STA C_XH,Y
  LDA #0
  STA C_FACE,Y
  LDA #$80
  STA C_VXL,Y
  LDA #$01
  STA C_VXH,Y
.eh_snd:
  PHX
  LDA #W_HATCH
  LDX #2
  JSR SFX_WHISTLE
  PLX
  RTS


; ===============================================================
;  PTERODACTYL: it hunts the nearest player; only a lance in the
;  beak kills it
; ===============================================================
CHECK_PTERO_TIME:
  LDA PT_ST
  BNE .cp_r
  LDA WTYPE
  CMP #4
  BEQ .cp_r
  CMP #5
  BNE .cp_long
  LDA WTH                      ; pterodactyl wave: after 300 frames
  BEQ .cp_r
  CMP #1
  BNE .cp_go
  LDA WTL
  CMP #$2C
  BCC .cp_r
  BRA .cp_go
.cp_long:
  LDA WAVEN                    ; any other wave from the 2nd: after a minute
  CMP #2
  BCC .cp_r
  LDA WTH
  CMP #$0E
  BCC .cp_r
  BNE .cp_go
  LDA WTL
  CMP #$10
  BCC .cp_r
.cp_go:
  JMP SPAWN_PTERO
.cp_r:
  RTS

SPAWN_PTERO:
  LDA #1
  STA PT_ST
  STZ PT_XL
  STZ PT_YL
  STZ PT_VYL
  STZ PT_VYH
  LDA RND
  AND #$1F
  CLC
  ADC #60
  STA PT_YH
  LDA RND
  AND #$02
  BEQ .sp_l
  LDA #252
  STA PT_XH
  LDA #1
  STA PT_FACE
  LDA #$00
  STA PT_VXL
  LDA #$FE
  STA PT_VXH
  BRA .sp_s
.sp_l:
  LDA #4
  STA PT_XH
  STZ PT_FACE
  STZ PT_VXL
  LDA #$02
  STA PT_VXH
.sp_s:
  LDA #W_PTERO
  LDX #2
  JMP SFX_WHISTLE

UPDATE_PTERO:
  LDA PT_ST
  BNE .pu_go
  RTS
.pu_go:
  LDA #$FF                     ; ---- the nearest player
  STA T6
  STA T7
  LDY #1
.pu_np:
  LDA C_ST,Y
  CMP #1
  BNE .pu_nn
  LDA C_XH,Y
  SEC
  SBC PT_XH
  BPL .pu_a
  EOR #$FF
  CLC
  ADC #1
.pu_a:
  CMP T6
  BCS .pu_nn
  STA T6
  STY T7
.pu_nn:
  DEY
  BPL .pu_np
  LDY T7
  BMI .pu_move
  LDA PT_VXL                   ; ---- towards him
  STA T0
  LDA PT_VXH
  STA T1
  LDA #$18
  STA T2
  LDA #$40
  STA T3
  LDA #$02
  STA T4
  LDA C_XH,Y
  SEC
  SBC PT_XH
  ASL A                        ; carry = he is on the left
  JSR ACCEL16
  LDA T0
  STA PT_VXL
  LDA T1
  STA PT_VXH
  LDA PT_VYL
  STA T0
  LDA PT_VYH
  STA T1
  LDA #$10
  STA T2
  LDA #$80
  STA T3
  LDA #$01
  STA T4
  LDY T7
  LDA C_YH,Y
  SEC
  SBC PT_YH
  ASL A                        ; carry = he is higher
  JSR ACCEL16
  LDA T0
  STA PT_VYL
  LDA T1
  STA PT_VYH
.pu_move:
  CLC                          ; ---- move (the field wraps)
  LDA PT_XL
  ADC PT_VXL
  STA PT_XL
  LDA PT_XH
  ADC PT_VXH
  STA PT_XH
  CLC
  LDA PT_YL
  ADC PT_VYL
  STA PT_YL
  LDA PT_YH
  ADC PT_VYH
  STA PT_YH
  CMP #CEIL_Y
  BCS .pu_c1
  LDA #CEIL_Y
  STA PT_YH
  STZ PT_VYL
  STZ PT_VYH
.pu_c1:
  LDA PT_YH
  CMP #150
  BCC .pu_c2
  LDA #150
  STA PT_YH
  STZ PT_VYL
  STZ PT_VYH
.pu_c2:
  LDA PT_VXH
  ROL A
  LDA #0
  ROL A
  STA PT_FACE                  ; 1 = going left
  LDA FRAME_CNT                ; ---- its cry
  AND #$7F
  BNE .pu_hit
  LDA #W_PTERO
  LDX #2
  JSR SFX_WHISTLE
.pu_hit:
  LDX #1                       ; ---- the players it touches
.pu_hl:
  STX CI
  LDA C_ST,X
  CMP #1
  BNE .pu_hn
  LDA C_XH,X
  SEC
  SBC PT_XH
  STA DXV
  BPL .pu_dx
  EOR #$FF
  CLC
  ADC #1
.pu_dx:
  CMP #14
  BCS .pu_hn
  LDA C_YH,X
  SEC
  SBC PT_YH
  BPL .pu_dy
  EOR #$FF
  CLC
  ADC #1
.pu_dy:
  CMP #12
  BCS .pu_hn
  STA DYV
  LDA DYV                      ; in the beak: the player is in front of it, at its height
  CMP #7
  BCS .pu_bite
  LDA DXV
  ROL A
  LDA #0
  ROL A                        ; 1 = the player is on its left
  CMP PT_FACE
  BNE .pu_bite
  JMP PTERO_KILL
.pu_bite:
  LDA C_T,X
  BNE .pu_hn                   ; still safe
  LDA #$FF
  STA KILLER
  JSR KILL_PLAYER
.pu_hn:
  LDX CI
  DEX
  BPL .pu_hl
  RTS

; X = player that hit the pterodactyl in the beak: 1000
PTERO_KILL:
  STZ PT_ST
  STZ WTL                      ; another one comes later
  STZ WTH
  LDA #$00
  STA PTS_L
  LDA #$10
  STA PTS_M
  JSR ADD_SCORE
  LDA #W_JOUST
  JSR SFX_WHISTLE
  LDA PT_XH
  STA T0
  LDA PT_YH
  STA T1
  LDA #0
  JSR NEW_FX
  LDA #S_SMALL
  LDY PT_XH
  JMP BOOM_AT

; T0 / T1 = speed 8.8 signed, T2 = step, T3 / T4 = top speed;
; carry clear = faster to the right (down), set = to the left (up)
ACCEL16:
  BCS .ac_neg
  CLC
  LDA T0
  ADC T2
  STA T0
  LDA T1
  ADC #0
  STA T1
  SEC
  LDA T0
  SBC T3
  LDA T1
  SBC T4
  BMI .ac_r
  LDA T3
  STA T0
  LDA T4
  STA T1
.ac_r:
  RTS
.ac_neg:
  SEC
  LDA T0
  SBC T2
  STA T0
  LDA T1
  SBC #0
  STA T1
  CLC
  LDA T0
  ADC T3
  LDA T1
  ADC T4
  BPL .ac_r
  SEC
  LDA #0
  SBC T3
  STA T0
  LDA #0
  SBC T4
  STA T1
  RTS


; ===============================================================
;  THE TROLL: its hand comes out of the lava for who flies low
; ===============================================================
UPDATE_TROLL:
  LDA TR_ST
  BNE .tr_act
  LDA TR_CD
  BEQ .tr_scan
  DEC TR_CD
  RTS
.tr_scan:
  LDX #(NC-1)
.ts_l:
  LDA C_ST,X
  CMP #1
  BNE .ts_n
  LDA C_GND,X
  BNE .ts_n
  LDA C_YH,X
  CMP #GRAB_Y
  BCC .ts_n
  JSR OVER_LAVA
  BCC .ts_n
  STX TR_C
  LDA C_XH,X
  STA TR_X
  LDA #1
  STA TR_ST
  STZ TR_H
  LDA #W_TROLL
  LDX #2
  JMP SFX_WHISTLE
.ts_n:
  DEX
  BPL .ts_l
  RTS
.tr_act:
  CMP #1
  BNE .tr_2
  LDX TR_C                     ; ---- the hand comes up
  LDA C_ST,X
  CMP #1
  BNE .tr_back
  LDA C_YH,X
  CMP #(GRAB_Y-14)
  BCC .tr_back                 ; he flew away
  LDA C_XH,X                   ; it follows him
  CMP TR_X
  BEQ .tr_up
  BCC .tr_xl
  INC TR_X
  BRA .tr_up
.tr_xl:
  DEC TR_X
.tr_up:
  LDA TR_H
  CMP #30
  BCS .tr_grab
  INC TR_H
  RTS
.tr_grab:
  LDA C_XH,X                   ; close enough to take him?
  SEC
  SBC TR_X
  BPL .tr_g1
  EOR #$FF
  CLC
  ADC #1
.tr_g1:
  CMP #10
  BCS .tr_r
  LDA C_YH,X
  CMP #(GRAB_Y-4)
  BCC .tr_r
  LDA #5
  STA C_ST,X
  LDA #2
  STA TR_ST
  STZ C_VXL,X
  STZ C_VXH,X
  STZ C_VYL,X
  STZ C_VYH,X
.tr_r:
  RTS
.tr_back:
  LDA #3
  STA TR_ST
  RTS
.tr_2:
  CMP #2
  BNE .tr_3
  LDX TR_C                     ; ---- it pulls him into the lava
  LDA TR_X
  STA C_XH,X
  INC C_YH,X
  LDA C_YH,X
  CMP #LAVA_CY
  BCC .tr_r
  LDA #1
  STA C_ST,X
  JSR LAVA_DEATH
  LDA #3
  STA TR_ST
  LDA #8
  STA TR_H
  RTS
.tr_3:
  LDA TR_H                     ; ---- back down
  SEC
  SBC #2
  BCC .tr_end
  BEQ .tr_end
  STA TR_H
  RTS
.tr_end:
  STZ TR_ST
  STZ TR_H
  LDA #90
  STA TR_CD
  RTS

; X = creature: carry set = no platform of the bottom under it (lava)
OVER_LAVA:
  LDY #2
.ol_l:
  LDA PF_ON,Y
  BEQ .ol_n
  LDA C_XH,X
  CMP PF_X1,Y
  BCC .ol_n
  LDA PF_X2,Y
  CMP C_XH,X
  BCC .ol_n
  CLC
  RTS
.ol_n:
  DEY
  BPL .ol_l
  SEC
  RTS


; ===============================================================
;  THE BRIDGE OVER THE LAVA burns a tile at a time from wave 3
; ===============================================================
UPDATE_BRIDGE:
  LDA WAVEN
  CMP #3
  BCC .ub_r
  LDA WSTATE
  CMP #1
  BNE .ub_r
  LDA BR_BT
  BEQ .ub_wait
  DEC BR_BT
  BEQ .ub_gone
  LDA BR_BT                    ; ---- the tile in flames
  AND #$07
  BNE .ub_r
  JSR BURN_COL
  TAY
  LDX #21
  JSR NT_XY
  LDA BR_BT
  AND #$08
  BEQ .ub_a
  LDA #T_BURN_B
  BRA .ub_p
.ub_a:
  LDA #T_BURN_A
.ub_p:
  STA VDATA
.ub_r:
  RTS
.ub_gone:
  JSR BURN_COL                 ; ---- it falls into the lava
  TAY
  LDX #21
  JSR NT_XY
  LDA #$00
  STA VDATA
  LDA BR_BSIDE
  BNE .ub_rr
  INC BR_L
  BRA .ub_ext
.ub_rr:
  INC BR_R
.ub_ext:
  JSR BRIDGE_EXTENT
  LDA #75
  SEC
  SBC WAVEN
  BCC .ub_m
  CMP #30
  BCS .ub_t
.ub_m:
  LDA #30
.ub_t:
  STA BRN_T
  LDA #S_LAVA
  LDX #2
  JMP SFX_BOOM
.ub_wait:
  LDA FRAME_CNT
  AND #$03
  BNE .ub_r
  LDA BRN_T
  BEQ .ub_start
  DEC BRN_T
  RTS
.ub_start:
  LDA BR_TOG                   ; ---- the next tile, on the other side
  EOR #$01
  STA BR_TOG
  STA BR_BSIDE
  JSR SIDE_LEFT
  BCC .ub_go
  LDA BR_BSIDE
  EOR #$01
  STA BR_BSIDE
  JSR SIDE_LEFT
  BCC .ub_go
  LDA #255                     ; nothing left to burn
  STA BRN_T
  RTS
.ub_go:
  LDA #90
  STA BR_BT
  RTS

; carry clear = the side BR_BSIDE still has tiles
SIDE_LEFT:
  LDA BR_BSIDE
  BNE .sl_r
  LDA BR_L
  CMP #9
  RTS
.sl_r:
  LDA BR_R
  CMP #9
  RTS

; A = column of the tile burning
BURN_COL:
  LDA BR_BSIDE
  BNE .bc_r
  LDA BR_L
  RTS
.bc_r:
  LDA #31
  SEC
  SBC BR_R
  RTS


; ===============================================================
;  SMALL EFFECTS: explosions and sparkles
; ===============================================================
; A = kind (0 explosion, 1 sparkle), T0 / T1 = where (keeps X, Y)
NEW_FX:
  PHX
  STA SMT1
  LDX #(NFX-1)
.nf_l:
  LDA FX_T,X
  BEQ .nf_f
  DEX
  BPL .nf_l
  PLX
  RTS
.nf_f:
  LDA #24
  STA FX_T,X
  LDA T0
  STA FX_X,X
  LDA T1
  STA FX_Y,X
  LDA SMT1
  STA FX_K,X
  PLX
  RTS

UPDATE_FX:
  LDX #(NFX-1)
.uf_l:
  LDA FX_T,X
  BEQ .uf_n
  DEC FX_T,X
.uf_n:
  DEX
  BPL .uf_l
  RTS


; ===============================================================
;  SPRITES: players first (they never flicker), then the
;  pterodactyl, the riders and the eggs in an order that turns
;  every frame (with more than 4 on a line they flicker instead of
;  disappearing), the hand of the troll and the effects
; ===============================================================
BUILD_SAT:
  STZ SPRI
  LDX #0
  JSR DRAW_CR
  LDX #1
  JSR DRAW_CR
  JSR DRAW_PTERO
  LDA FRAME_CNT
  AND #$07
  STA RR
  LDY #0
.bs_r:
  STY CJ
  TYA
  CLC
  ADC RR
  AND #$07
  CLC
  ADC #2
  TAX
  JSR DRAW_CR
  LDY CJ
  INY
  CPY #8
  BNE .bs_r
  LDY #0
.bs_e:
  STY CJ
  TYA
  CLC
  ADC RR
  AND #$07
  TAX
  JSR DRAW_EGG
  LDY CJ
  INY
  CPY #8
  BNE .bs_e
  JSR DRAW_TROLL
  LDX #(NFX-1)
.bs_f:
  STX CJ
  JSR DRAW_FX
  LDX CJ
  DEX
  BPL .bs_f
  LDX SPRI
  LDA #$D0
  STA SAT_BUFFER,X
  INX
  STX SATB
  RTS

ADD_BOTH:
  JSR ADD_SPR
  JMP ADD_SPR_WRAP

; X = creature
DRAW_CR:
  LDA C_ST,X
  BNE .dc_go
  RTS
.dc_go:
  STX DSL
  LDY C_XH,X
  STY OX
  LDY C_YH,X
  STY OY
  CMP #2
  BEQ .dc_die
  CMP #3
  BEQ .dc_come
  LDA C_TY,X
  BNE .dc_pos
  LDA C_T,X                    ; a player still safe blinks
  BEQ .dc_pos
  LDA FRAME_CNT
  AND #$04
  BNE .dc_pos
  RTS
.dc_pos:
  JSR CR_FRAME
  ASL A
  ASL A
  ASL A
  STA T7
  LDA C_FACE,X
  ASL A
  ASL A
  ORA T7
  STA T7                       ; (frame * 2 + direction) * 4
  LDA C_TY,X
  BEQ .dc_pl
  TAY
  LDA TY_COL,Y
  STA OC
  LDA T7
  CLC
  ADC #PT_BUZZ
  STA ON
  JMP ADD_BOTH
.dc_pl:
  LDA PLR_COL,X                ; the knight on top, then his bird
  STA OC
  LDA T7
  CLC
  ADC #PT_RIDER
  STA ON
  JSR ADD_BOTH
  LDX DSL
  LDA PLM_COL,X
  STA OC
  LDA T7
  CLC
  ADC #PT_MOUNT
  STA ON
  JMP ADD_BOTH
.dc_die:                       ; the player explodes
  LDA C_T,X
  LSR A
  LSR A
  LSR A
  LSR A
  CMP #3
  BCC .dc_d1
  LDA #2
.dc_d1:
  EOR #$FF
  CLC
  ADC #3
  TAY
  LDA EXPL_N,Y
  STA ON
  LDA EXPL_C,Y
  STA OC
  JMP ADD_BOTH
.dc_come:                      ; sparkle before it appears
  LDA C_T,X
  LSR A
  LSR A
  LSR A
  LSR A
  CMP #3
  BCC .dc_c1
  LDA #2
.dc_c1:
  TAY
  LDA SPARK_N,Y
  STA ON
  LDA FRAME_CNT
  AND #$03
  TAY
  LDA SPARK_C,Y
  STA OC
  JMP ADD_BOTH

; X = creature: A = frame (0 stand, 1-2 steps, 3 gliding, 4 wings up) (keeps X)
CR_FRAME:
  LDA C_GND,X
  BEQ .cf_air
  LDA C_VXL,X
  ORA C_VXH,X
  BEQ .cf_st
  LDA C_ANIM,X
  LSR A
  LSR A
  AND #$01
  INC A
  RTS
.cf_st:
  LDA #0
  RTS
.cf_air:
  LDA C_FLT,X
  CMP #4
  LDA #3
  BCC .cf_r
  LDA #4
.cf_r:
  RTS

; X = egg
DRAW_EGG:
  LDA E_ST,X
  BNE .dg_go
  RTS
.dg_go:
  LDY E_XH,X
  STY OX
  LDY E_YH,X
  STY OY
  CMP #3
  BEQ .dg_h
  LDA #PT_EGG
  STA ON
  LDA #$0F
  STA OC
  LDA E_ST,X                   ; about to hatch: it flashes
  CMP #2
  BNE .dg_c
  LDA E_T,X
  CMP #8
  BCS .dg_c
  LDA FRAME_CNT
  AND #$04
  BEQ .dg_c
  LDA #$0B
  STA OC
.dg_c:
  JMP ADD_BOTH
.dg_h:
  LDA #(PT_EGG+4)              ; hatched: the rider waits for his buzzard
  STA ON
  LDA FRAME_CNT
  AND #$04
  BEQ .dg_w
  LDA #$0B
  BRA .dg_s
.dg_w:
  LDA #$0F
.dg_s:
  STA OC
  JMP ADD_BOTH

DRAW_PTERO:
  LDA PT_ST
  BNE .dp_go
  RTS
.dp_go:
  LDA PT_XH
  STA OX
  LDA PT_YH
  STA OY
  LDA FRAME_CNT                ; two frames of the wings
  AND #$08
  STA T7
  LDA PT_FACE
  ASL A
  ASL A
  ORA T7
  CLC
  ADC #PT_PTERO
  STA ON
  LDA #$0A
  STA OC
  JMP ADD_BOTH

DRAW_TROLL:
  LDA TR_ST
  BNE .dt_go
  RTS
.dt_go:
  LDA TR_X
  STA OX
  LDA #$0C
  STA OC
  LDA TR_ST
  CMP #2
  BEQ .dt_hold
  LDA #192
  SEC
  SBC TR_H
  STA OY
  LDA #(PT_HAND+4)             ; open while it comes up
  LDY TR_ST
  CPY #1
  BEQ .dt_s
  LDA #PT_HAND
.dt_s:
  STA ON
  JMP ADD_SPR
.dt_hold:
  LDX TR_C                     ; closed on the creature
  LDA C_YH,X
  CLC
  ADC #12
  STA OY
  LDA #PT_HAND
  STA ON
  JMP ADD_SPR

; X = effect
DRAW_FX:
  LDA FX_T,X
  BNE .dx_go
  RTS
.dx_go:
  LDA FX_X,X
  STA OX
  LDA FX_Y,X
  STA OY
  LDA #24
  SEC
  SBC FX_T,X
  LSR A
  LSR A
  LSR A
  TAY
  LDA FX_K,X
  BNE .dx_sp
  LDA EXPL_N,Y
  STA ON
  LDA EXPL_C,Y
  STA OC
  JMP ADD_BOTH
.dx_sp:
  LDA SPARK_N,Y
  STA ON
  LDA SPARK_C,Y
  STA OC
  JMP ADD_BOTH


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

; the whole name table to tile 0
CLEAR_NT:
  LDA #$00
  STA T0
  LDA #(VDP_WRITE_VRAM_BIT | >VDP_NAME_TABLE_BASE)
  STA T1
  LDA #$00
  STA T2
  LDA #$03
  STA T3
  LDA #$00
  JMP VFILL

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

; rows 0-1: 1UP, HIGH SCORE, 2UP, the scores and the spare riders
DRAW_TOP:
  LDA #<TXT_TOP
  STA TP
  LDA #>TXT_TOP
  STA TP+1
  JSR PRINT
  LDX #1
  LDY #13
  JSR NT_XY
  LDA HISC+2
  JSR PUT_2
  LDA HISC+1
  JSR PUT_2
  LDA HISC
  JSR PUT_2
  LDX #$00
  JSR DRAW_SCORE
  JSR DRAW_LIVES
  LDX #$01
  JSR DRAW_SCORE
  ; fall into DRAW_LIVES

; X = player: spare riders on row 1 (5 cells, keeps X)
DRAW_LIVES:
  PHX
  LDY LV_COL,X
  LDX #1
  JSR NT_XY
  PLX
  LDA LIVES,X
  BEQ .dl_z
  SEC
  SBC #1                       ; the riders waiting (not the one flying)
.dl_z:
  STA T0
  LDY #$00
.dl_l:
  LDA #$20
  CPY T0
  BCS .dl_b
  LDA #T_LIFE
.dl_b:
  STA VDATA
  INY
  CPY #5
  BNE .dl_l
  RTS

; X = player: his score on row 1 (keeps X)
DRAW_SCORE:
  PHX
  LDY SC_COL,X
  LDX #1
  JSR NT_XY
  PLX
  LDA SCH,X
  JSR PUT_2
  LDA SCM,X
  JSR PUT_2
  LDA SCL,X
  JMP PUT_2

; the wave number under the high score (keeps X)
DRAW_WAVE:
  PHX
  LDX #2
  LDY #12
  JSR NT_XY
  LDA #<TXT_WAVE
  STA TP
  LDA #>TXT_WAVE
  STA TP+1
  LDY #$00
.dw_l:
  LDA (TP),Y
  BEQ .dw_n
  STA VDATA
  INY
  BRA .dw_l
.dw_n:
  LDA WAVEN
  JSR BIN2BCD
  JSR PUT_2
  PLX
  RTS

; ---------------------------------------------------------------
; platform pieces: A = platform index. Draws its tiles (keeps nothing)
; ---------------------------------------------------------------
DRAW_PF:
  TAX
  LDA PF_Y,X
  LSR A
  LSR A
  LSR A
  STA T5                       ; row
  LDA PF_X1,X
  LSR A
  LSR A
  LSR A
  STA T3                       ; first column
  LDA PF_X2,X
  LSR A
  LSR A
  LSR A
  STA T4                       ; last column
  LDA PF_KIND,X                ; 0 rock, 1 bridge
  STA T2
  LDX T5
  LDY T3
  JSR NT_XY
  LDX T3
.dp_l:
  LDA T2
  BEQ .dp_rock
  LDA #T_BRIDGE
  BRA .dp_put
.dp_rock:
  LDA #T_PFM
  CPX T3
  BNE .dp_n1
  LDA #T_PFL
.dp_n1:
  CPX T4
  BNE .dp_put
  CPX T3
  BEQ .dp_s
  LDA #T_PFR
  BRA .dp_put
.dp_s:
  LDA #T_PFS
.dp_put:
  STA VDATA
  CPX T4
  BEQ .dp_e
  INX
  BRA .dp_l
.dp_e:
  RTS

; the two rows of lava; LAVAPH alternates the crests (VDP free)
DRAW_LAVA:
  LDX #22
  LDY #0
  JSR NT_XY
  LDA LAVAPH
  AND #$01
  STA T0
  LDX #32
.dv_l:
  LDA T0
  BEQ .dv_a
  LDA #T_LAVA_B
  BRA .dv_p
.dv_a:
  LDA #T_LAVA_A
.dv_p:
  STA VDATA
  LDA T0
  EOR #$01
  STA T0
  DEX
  BNE .dv_l
  RTS

DRAW_LAVA_DEEP:
  LDX #23
  LDY #0
  JSR NT_XY
  LDA #T_LAVA_D
  LDX #32
.dd_l:
  STA VDATA
  DEX
  BNE .dd_l
  RTS


; ===============================================================
;  SPRITES
; ===============================================================
; a 16x16 sprite centred on (OX, OY), pattern ON, colour OC (32 at most)
ADD_SPR:
  LDX SPRI
  CPX #128
  BCS .as_r
  LDA OY
  SEC
  SBC #9
  STA SAT_BUFFER,X
  LDA ON
  STA SAT_BUFFER+2,X
  LDA OX
  SEC
  SBC #8
  BCC .as_ec
  STA SAT_BUFFER+1,X
  LDA OC
  STA SAT_BUFFER+3,X
  BRA .as_n
.as_ec:
  CLC                          ; near the left edge: early clock
  ADC #32
  STA SAT_BUFFER+1,X
  LDA OC
  ORA #$80
  STA SAT_BUFFER+3,X
.as_n:
  TXA
  CLC
  ADC #4
  STA SPRI
.as_r:
  RTS

; the other half of a sprite that crosses the edge of the screen (the field wraps)
ADD_SPR_WRAP:
  LDA OX
  CMP #248
  BCS .aw_right
  CMP #8
  BCS .aw_r
  LDX SPRI                     ; near the left edge: the part that comes out on the right
  CPX #128
  BCS .aw_r
  LDA OY
  SEC
  SBC #9
  STA SAT_BUFFER,X
  LDA ON
  STA SAT_BUFFER+2,X
  LDA OX
  CLC
  ADC #248
  STA SAT_BUFFER+1,X
  LDA OC
  STA SAT_BUFFER+3,X
  BRA .aw_n
.aw_right:                     ; near the right edge: the part that comes out on the left
  LDX SPRI
  CPX #128
  BCS .aw_r
  LDA OY
  SEC
  SBC #9
  STA SAT_BUFFER,X
  LDA ON
  STA SAT_BUFFER+2,X
  LDA OX
  SEC
  SBC #232
  STA SAT_BUFFER+1,X
  LDA OC
  ORA #$80
  STA SAT_BUFFER+3,X
.aw_n:
  TXA
  CLC
  ADC #4
  STA SPRI
.aw_r:
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
BOOM_AT:
  LDX #$00
  CPY #$80
  BCC .ba_l
  INX
.ba_l:
  JMP SFX_BOOM

; ===============================================================
;  LIBRARY (from lunar_lander): joystick, frames, VDP
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
;  TABLES
; ===============================================================
SC_COL:     .byte 0,26                         ; score of player 1 / 2: column on row 1
LV_COL:     .byte 7,20                         ; his spare riders (5 cells)
BITS:       .byte 1,2
PL_START_X: .byte 100,156                      ; players on the ground
PL_START_F: .byte 0,1
PLR_COL:    .byte $05,$0D                      ; knight of player 1 / 2
PLM_COL:    .byte $0B,$0F                      ; ostrich / stork
; by kind: 0 player, 1 bounder, 2 hunter, 3 shadow lord
ACC_T:      .byte $18,$10,$18,$1C              ; acceleration (8.8)
VMX_L:      .byte $80,$50,$00,$C0              ; top speed: 2.5, 1.3, 2.0, 2.75 pixels per frame
VMX_H:      .byte $02,$01,$02,$02
TY_PL:      .byte $00,$00,$50,$00              ; points (BCD): 500, 750, 1500
TY_PM:      .byte $00,$05,$07,$15
TY_COL:     .byte $00,$08,$0E,$05              ; red, grey, blue
FLAP_CD:    .byte 0,14,10,7                    ; frames between two flaps
AI_T:       .byte 0,40,24,16                   ; frames between two plans (+ 0-15)
; eggs picked up in a row: 250, 500, 750, 1000
EGG_PL:     .byte $50,$00,$50,$00
EGG_PM:     .byte $02,$05,$07,$10
; sprites of the effects
EXPL_N:     .byte PT_EXPL,PT_EXPL+4,PT_EXPL+8
EXPL_C:     .byte $0B,$0A,$09
SPARK_N:    .byte PT_SPARK,PT_SPARK+4,PT_SPARK+8
SPARK_C:    .byte $0F,$0B,$0A,$0B
; the egg wave: where the eggs fall from
EGGW_X:     .byte 100,128,156,20,236,90,166,40
EGGW_Y:     .byte 30,36,30,56,56,88,88,112

; ---------------------------------------------------------------
; platforms: 0 ground, 1-2 bridge over the lava, 3 top, 4-5 upper
; ledges, 6 middle, 7-8 lower ledges
; ---------------------------------------------------------------
PF_KIND:    .byte 0,1,1,0,0,0,0,0,0            ; 0 rock, 1 bridge
PF_X1_T:    .byte 72,0,184,88,0,208,72,0,200
PF_X2_T:    .byte 183,71,255,167,47,255,183,55,255
PF_Y_T:     .byte 168,168,168,48,72,72,104,128,128
; the platforms by position in the cycle of 5 waves
PF_INIT_ON:
  .byte 1,1,1,1,1,1,1,1,1
  .byte 1,1,1,1,1,1,1,1,1
  .byte 1,1,1,1,1,1,1,0,0
  .byte 1,1,1,1,0,0,1,0,0
  .byte 1,1,1,1,1,1,1,1,1
; spawn points: X, centre Y of a rider standing there, platform
PAD_X:      .byte 128,24,232,128,128
PAD_Y:      .byte 40,64,64,96,160
PAD_PF:     .byte 3,4,5,6,0

; title: the knight, a buzzard and the scoring table (sprite Y, X, pattern, colour)
TITLE_SY:   .byte 15,15,15,9*8-5,11*8-5,13*8-5,15*8-5,17*8-5
TITLE_SX:   .byte 64,64,176,56,56,56,56,56
TITLE_SN:   .byte PT_RIDER+24,PT_MOUNT+24,PT_BUZZ+36,PT_BUZZ+24,PT_BUZZ+24,PT_BUZZ+24,PT_PTERO,PT_EGG
TITLE_SC:   .byte $05,$0B,$08,$08,$0E,$05,$0A,$0F

; text records: row, column, characters, 0   (end of list: $FF)
TXT_TOP:
  .byte 0,1,"1UP",0
  .byte 0,11,"HIGH SCORE",0
  .byte 0,28,"2UP",0
  .byte $FF
TXT_WAVE:
  .byte "WAVE ",0
TXT_TITLE:
  .byte 7,8,"- SCORE TABLE -",0
  .byte 9,10,"BOUNDER      500",0
  .byte 11,10,"HUNTER       750",0
  .byte 13,10,"SHADOW LORD 1500",0
  .byte 15,10,"PTERODACTYL 1000",0
  .byte 17,10,"EGG  250 TO 1000",0
  .byte 18,10,"IN THE AIR  +500",0
  .byte 20,1,"B1 = 1 PLAYER   B2 = 2 PLAYERS",0
  .byte $FF
BAN_LO:     .byte <TXT_B0,<TXT_B1,<TXT_B2,<TXT_B3,<TXT_B4,<TXT_B5
BAN_HI:     .byte >TXT_B0,>TXT_B1,>TXT_B2,>TXT_B3,>TXT_B4,>TXT_B5
TXT_B0:
  .byte 10,8,"PREPARE TO JOUST",0
  .byte $FF
TXT_B1:
  .byte 10,9,"SURVIVAL WAVE",0
  .byte 11,6,"NO RIDER LOST = 3000",0
  .byte $FF
TXT_B2:
  .byte 10,11,"TEAM WAVE",0
  .byte 11,4,"NOBODY HITS = 3000 EACH",0
  .byte $FF
TXT_B3:
  .byte 10,9,"GLADIATOR WAVE",0
  .byte 11,5,"FIRST TO UNSEAT = 3000",0
  .byte $FF
TXT_B4:
  .byte 10,12,"EGG WAVE",0
  .byte $FF
TXT_B5:
  .byte 10,5,"BEWARE THE PTERODACTYL",0
  .byte $FF
TXT_BONUS:
  .byte 11,11,"BONUS 3000",0
  .byte $FF
TXT_OVER:
  .byte 11,11,"GAME OVER",0
  .byte $FF

; ---------------------------------------------------------------
; music (from tank): per track 0 melody / 1 harmony / 2 bass
; ---------------------------------------------------------------
V0_TAB:        .byte 13, 9, 12, 0      ; volume at the attack of the note
FLOOR_TAB:     .byte 8, 5, 7, 0        ; lowest volume reached by the decay
DECMASK_TAB:   .byte 3, 7, 3, 0        ; the volume drops by 1 when (age AND mask) = 0
; drums: 1 kick, 2 snare, 3 hi-hat, 4 cymbal
DRUM_NP:       .byte 0, 28, 10, 2, 5
DRUM_V0:       .byte 0, 15, 14, 8, 15
DRUM_MASK:     .byte 0, 0, 0, 0, 7

SONGP_LO:      .byte <START_LEAD,<START_HARM,<START_BASS,<START_DRUM
SONGP_HI:      .byte >START_LEAD,>START_HARM,>START_BASS,>START_DRUM

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

; the start tune of a game: a short fanfare in C (composed for this version), 160 frames
;   G4 32  C5 37  E5 41  G5 44  A5 46  C6 49  D6 51  E6 53
START_LEAD:
  .byte 32,5, 37,5, 41,5, 44,15, 41,5, 44,5, 49,25, 0,5
  .byte 46,5, 49,5, 51,5, 53,20, 51,5, 49,5, 46,10, 49,30
  .byte $FF
START_HARM:
  .byte 29,40, 32,40, 34,40, 32,40
  .byte $FF
START_BASS:
  .byte 13,20, 20,20, 18,20, 20,20
  .byte 13,20, 20,20, 15,20, 13,20
  .byte $FF
START_DRUM:
  .byte 1,10, 3,10, 2,10, 3,10, 1,10, 3,10, 2,10, 3,10
  .byte 1,10, 3,10, 2,10, 3,10, 1,10, 1,10, 4,20
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
; Joust: generated by dev/gen_joust.js (do not edit by hand)

; tiles from 96
T_PFL = 96
T_PFM = 97
T_PFR = 98
T_PFS = 99
T_LAVA_A = 100
T_LAVA_B = 101
T_LAVA_D = 102
T_BRIDGE = 103
T_BURN_A = 104
T_BURN_B = 105
T_LIFE = 106
TILE_PAT:
  .byte $7F,$DD,$BD,$FF,$B7,$EF,$DD,$7F,$FF,$DD,$BD,$FF,$B7,$EF,$DD,$FF
  .byte $FE,$BB,$BD,$FF,$ED,$F7,$BB,$FE,$7E,$DD,$BD,$FF,$B7,$EF,$DD,$7E
  .byte $22,$77,$FF,$DE,$FF,$BD,$FF,$EF,$88,$EE,$FF,$7B,$FF,$DE,$FF,$F7
  .byte $FF,$BF,$FF,$F7,$FF,$DF,$FF,$FE,$FF,$DB,$FF,$BD,$FF,$DB,$FF,$BD
  .byte $AA,$FF,$DB,$FF,$5A,$FF,$DB,$FF,$55,$FF,$6D,$FF,$AB,$FF,$B6,$FF
  .byte $3C,$7E,$66,$7E,$3C,$18,$3C,$5A
TILE_COL:
  .byte $BA,$A6,$A6,$A6,$A6,$A6,$A6,$A6,$BA,$A6,$A6,$A6,$A6,$A6,$A6,$A6
  .byte $BA,$A6,$A6,$A6,$A6,$A6,$A6,$A6,$BA,$A6,$A6,$A6,$A6,$A6,$A6,$A6
  .byte $80,$80,$8B,$8B,$8B,$8B,$8B,$8B,$80,$80,$8B,$8B,$8B,$8B,$8B,$8B
  .byte $68,$68,$68,$68,$68,$68,$68,$68,$B9,$A9,$A9,$A9,$A9,$A9,$A9,$A9
  .byte $B0,$B8,$98,$88,$98,$88,$68,$68,$80,$B8,$88,$98,$88,$98,$68,$68
  .byte $B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0

; big letters of the title: J O U S T, 4 tiles each (192-211)
BIG_P:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$18,$18,$18,$18,$18,$18,$18
  .byte $00,$00,$00,$18,$18,$07,$07,$00,$18,$18,$18,$18,$18,$E0,$E0,$00
  .byte $00,$07,$07,$18,$18,$18,$18,$18,$00,$E0,$E0,$18,$18,$18,$18,$18
  .byte $18,$18,$18,$18,$18,$07,$07,$00,$18,$18,$18,$18,$18,$E0,$E0,$00
  .byte $00,$18,$18,$18,$18,$18,$18,$18,$00,$18,$18,$18,$18,$18,$18,$18
  .byte $18,$18,$18,$18,$18,$07,$07,$00,$18,$18,$18,$18,$18,$E0,$E0,$00
  .byte $00,$07,$07,$18,$18,$18,$18,$07,$00,$E0,$E0,$18,$18,$00,$00,$E0
  .byte $07,$00,$00,$18,$18,$07,$07,$00,$E0,$18,$18,$18,$18,$E0,$E0,$00
  .byte $00,$1F,$1F,$01,$01,$01,$01,$01,$00,$F8,$F8,$80,$80,$80,$80,$80
  .byte $01,$01,$01,$01,$01,$01,$01,$00,$80,$80,$80,$80,$80,$80,$80,$00
BIG_C:
  .byte $B0,$B0,$B0,$B0,$90,$90,$90,$90,$B0,$B0,$B0,$B0,$90,$90,$90,$90
  .byte $90,$90,$80,$80,$80,$80,$60,$60,$90,$90,$80,$80,$80,$80,$60,$60
  .byte $B0,$B0,$B0,$B0,$90,$90,$90,$90,$B0,$B0,$B0,$B0,$90,$90,$90,$90
  .byte $90,$90,$80,$80,$80,$80,$60,$60,$90,$90,$80,$80,$80,$80,$60,$60
  .byte $B0,$B0,$B0,$B0,$90,$90,$90,$90,$B0,$B0,$B0,$B0,$90,$90,$90,$90
  .byte $90,$90,$80,$80,$80,$80,$60,$60,$90,$90,$80,$80,$80,$80,$60,$60
  .byte $B0,$B0,$B0,$B0,$90,$90,$90,$90,$B0,$B0,$B0,$B0,$90,$90,$90,$90
  .byte $90,$90,$80,$80,$80,$80,$60,$60,$90,$90,$80,$80,$80,$80,$60,$60
  .byte $B0,$B0,$B0,$B0,$90,$90,$90,$90,$B0,$B0,$B0,$B0,$90,$90,$90,$90
  .byte $90,$90,$80,$80,$80,$80,$60,$60,$90,$90,$80,$80,$80,$80,$60,$60

; big title (text records, end = $FF)
TXT_BIG:
  .byte 2,11,192,193,196,197,200,201,204,205,208,209,0
  .byte 3,11,194,195,198,199,202,203,206,207,210,211,0
  .byte $FF

; blocks loaded into the VRAM: kind (1 copy, 2 fill), address (with write bit), length, source / value
GFX_LOAD:
  .byte 1, $00,$41, <512,>512, <FONT,>FONT
  .byte 2, $00,$61, <512,>512, $F0,0
  .byte 1, $00,$43, <88,>88, <TILE_PAT,>TILE_PAT
  .byte 1, $00,$63, <88,>88, <TILE_COL,>TILE_COL
  .byte 1, $00,$49, <512,>512, <FONT,>FONT
  .byte 2, $00,$69, <512,>512, $F0,0
  .byte 1, $00,$4B, <88,>88, <TILE_PAT,>TILE_PAT
  .byte 1, $00,$6B, <88,>88, <TILE_COL,>TILE_COL
  .byte 1, $00,$51, <512,>512, <FONT,>FONT
  .byte 2, $00,$71, <512,>512, $F0,0
  .byte 1, $00,$53, <88,>88, <TILE_PAT,>TILE_PAT
  .byte 1, $00,$73, <88,>88, <TILE_COL,>TILE_COL
  .byte 1, $00,$46, <160,>160, <BIG_P,>BIG_P
  .byte 1, $00,$66, <160,>160, <BIG_C,>BIG_C
  .byte 0

; sprite patterns (16x16), value = pattern number * 4. Groups with two directions: (frame * 2 + dir) * 4 from the base, dir 0 = right, 1 = left
PT_MOUNT = 0
PT_RIDER = 40
PT_BUZZ = 80
PT_PTERO = 120
PT_EGG = 136
PT_HAND = 144
PT_SPARK = 152
PT_EXPL = 164
SPR_PAGES = 6
SPRITES:
;  0 PT_MOUNT 0 R, 4 PT_MOUNT 0 L, 8 PT_MOUNT 1 R, 12 PT_MOUNT 1 L, 16 PT_MOUNT 2 R, 20 PT_MOUNT 2 L, 24 PT_MOUNT 3 R, 28 PT_MOUNT 3 L, 32 PT_MOUNT 4 R, 36 PT_MOUNT 4 L, 40 PT_RIDER 0 R, 44 PT_RIDER 0 L, 48 PT_RIDER 1 R, 52 PT_RIDER 1 L, 56 PT_RIDER 2 R, 60 PT_RIDER 2 L, 64 PT_RIDER 3 R, 68 PT_RIDER 3 L, 72 PT_RIDER 4 R, 76 PT_RIDER 4 L, 80 PT_BUZZ 0 R, 84 PT_BUZZ 0 L, 88 PT_BUZZ 1 R, 92 PT_BUZZ 1 L, 96 PT_BUZZ 2 R, 100 PT_BUZZ 2 L, 104 PT_BUZZ 3 R, 108 PT_BUZZ 3 L, 112 PT_BUZZ 4 R, 116 PT_BUZZ 4 L, 120 PT_PTERO 0 R, 124 PT_PTERO 0 L, 128 PT_PTERO 1 R, 132 PT_PTERO 1 L, 136 PT_EGG 0, 140 PT_EGG 1, 144 PT_HAND 0, 148 PT_HAND 1, 152 PT_SPARK 0, 156 PT_SPARK 1, 160 PT_SPARK 2, 164 PT_EXPL 0, 168 PT_EXPL 1, 172 PT_EXPL 2
  .byte $00,$00,$00,$00,$00,$00,$00,$40,$6F,$FF,$7F,$3F,$0C,$0C,$0C,$1C
  .byte $00,$00,$3C,$3E,$38,$30,$30,$38,$D8,$F0,$F0,$E0,$60,$60,$60,$E0
  .byte $00,$00,$3C,$7C,$1C,$0C,$0C,$1C,$1B,$0F,$0F,$07,$06,$06,$06,$07
  .byte $00,$00,$00,$00,$00,$00,$00,$02,$F6,$FF,$FE,$FC,$30,$30,$30,$38
  .byte $00,$00,$00,$00,$00,$00,$00,$40,$6F,$FF,$7F,$3F,$18,$30,$30,$70
  .byte $00,$00,$3C,$3E,$38,$30,$30,$38,$D8,$F0,$F0,$E0,$30,$18,$0C,$07
  .byte $00,$00,$3C,$7C,$1C,$0C,$0C,$1C,$1B,$0F,$0F,$07,$0C,$18,$30,$E0
  .byte $00,$00,$00,$00,$00,$00,$00,$02,$F6,$FF,$FE,$FC,$18,$0C,$0C,$0E
  .byte $00,$00,$00,$00,$00,$00,$00,$40,$6F,$FF,$7F,$3F,$0E,$07,$06,$06
  .byte $00,$00,$3C,$3E,$38,$30,$30,$38,$D8,$F0,$F0,$E0,$E0,$C0,$C0,$C0
  .byte $00,$00,$3C,$7C,$1C,$0C,$0C,$1C,$1B,$0F,$0F,$07,$07,$03,$03,$03
  .byte $00,$00,$00,$00,$00,$00,$00,$02,$F6,$FF,$FE,$FC,$70,$E0,$60,$60
  .byte $00,$00,$00,$00,$00,$00,$00,$FF,$7F,$FF,$7F,$3F,$0E,$07,$00,$00
  .byte $00,$00,$3C,$3E,$38,$30,$30,$B8,$D8,$F0,$F0,$E0,$E0,$C0,$00,$00
  .byte $00,$00,$3C,$7C,$1C,$0C,$0C,$1D,$1B,$0F,$0F,$07,$07,$03,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$FF,$FE,$FF,$FE,$FC,$70,$E0,$00,$00
  .byte $80,$C0,$60,$70,$38,$3C,$1E,$5F,$6F,$FF,$7F,$3F,$0E,$07,$00,$00
  .byte $00,$00,$3C,$3E,$38,$30,$30,$38,$D8,$F0,$F0,$E0,$E0,$C0,$00,$00
  .byte $00,$00,$3C,$7C,$1C,$0C,$0C,$1C,$1B,$0F,$0F,$07,$07,$03,$00,$00
  .byte $01,$03,$06,$0E,$1C,$3C,$78,$FA,$F6,$FF,$FE,$FC,$70,$E0,$00,$00
  .byte $00,$0E,$1F,$1F,$0E,$1F,$3F,$3F,$1E,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$04,$0C,$38,$B0,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$20,$30,$1C,$0D,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$70,$F8,$F8,$70,$F8,$FC,$FC,$78,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$0E,$1F,$1F,$0E,$1F,$3F,$3F,$1E,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$04,$0C,$38,$B0,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$20,$30,$1C,$0D,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$70,$F8,$F8,$70,$F8,$FC,$FC,$78,$00,$00,$00,$00,$00,$00
  .byte $00,$0E,$1F,$1F,$0E,$1F,$3F,$3F,$1E,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$04,$0C,$38,$B0,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$20,$30,$1C,$0D,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$70,$F8,$F8,$70,$F8,$FC,$FC,$78,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$0E,$1F,$1F,$0E,$1F,$3F,$3F,$1E,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$04,$0C,$38,$B0,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$20,$30,$1C,$0D,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$70,$F8,$F8,$70,$F8,$FC,$FC,$78,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$0E,$1F,$1F,$0E,$1F,$3F,$3F,$1E,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$04,$0C,$38,$B0,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$20,$30,$1C,$0D,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$70,$F8,$F8,$70,$F8,$FC,$FC,$78,$00,$00,$00,$00,$00,$00
  .byte $00,$0E,$1F,$1F,$0E,$1F,$3F,$7F,$7F,$FF,$7F,$3F,$0C,$0C,$0C,$1C
  .byte $00,$00,$38,$3C,$3E,$38,$B0,$38,$D8,$F0,$F0,$E0,$60,$60,$60,$E0
  .byte $00,$00,$1C,$3C,$7C,$1C,$0D,$1C,$1B,$0F,$0F,$07,$06,$06,$06,$07
  .byte $00,$70,$F8,$F8,$70,$F8,$FC,$FE,$FE,$FF,$FE,$FC,$30,$30,$30,$38
  .byte $00,$00,$0E,$1F,$1F,$0E,$1F,$7F,$7F,$FF,$7F,$3F,$18,$30,$30,$70
  .byte $00,$00,$38,$3C,$3E,$3C,$38,$B8,$D8,$F0,$F0,$E0,$30,$18,$0C,$07
  .byte $00,$00,$1C,$3C,$7C,$3C,$1C,$1D,$1B,$0F,$0F,$07,$0C,$18,$30,$E0
  .byte $00,$00,$70,$F8,$F8,$70,$F8,$FE,$FE,$FF,$FE,$FC,$18,$0C,$0C,$0E
  .byte $00,$0E,$1F,$1F,$0E,$1F,$3F,$7F,$7F,$FF,$7F,$3F,$0E,$07,$06,$06
  .byte $00,$00,$38,$3C,$3E,$38,$B0,$38,$D8,$F0,$F0,$E0,$E0,$C0,$C0,$C0
  .byte $00,$00,$1C,$3C,$7C,$1C,$0D,$1C,$1B,$0F,$0F,$07,$07,$03,$03,$03
  .byte $00,$70,$F8,$F8,$70,$F8,$FC,$FE,$FE,$FF,$FE,$FC,$70,$E0,$60,$60
  .byte $00,$0E,$1F,$1F,$0E,$1F,$3F,$FF,$7F,$FF,$7F,$3F,$0E,$07,$00,$00
  .byte $00,$00,$38,$3C,$3E,$38,$B0,$B8,$D8,$F0,$F0,$E0,$E0,$C0,$00,$00
  .byte $00,$00,$1C,$3C,$7C,$1C,$0D,$1D,$1B,$0F,$0F,$07,$07,$03,$00,$00
  .byte $00,$70,$F8,$F8,$70,$F8,$FC,$FF,$FE,$FF,$FE,$FC,$70,$E0,$00,$00
  .byte $80,$C0,$6E,$7F,$3F,$3E,$1F,$7F,$7F,$FF,$7F,$3F,$0E,$07,$00,$00
  .byte $00,$00,$38,$3C,$3E,$3C,$38,$B8,$D8,$F0,$F0,$E0,$E0,$C0,$00,$00
  .byte $00,$00,$1C,$3C,$7C,$3C,$1C,$1D,$1B,$0F,$0F,$07,$07,$03,$00,$00
  .byte $01,$03,$76,$FE,$FC,$7C,$F8,$FE,$FE,$FF,$FE,$FC,$70,$E0,$00,$00
  .byte $00,$00,$00,$00,$20,$30,$18,$1C,$0F,$07,$03,$01,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$02,$06,$0C,$1C,$78,$FC,$FF,$FD,$F0,$60,$00,$00
  .byte $00,$00,$00,$00,$40,$60,$30,$38,$1E,$3F,$FF,$BF,$0F,$06,$00,$00
  .byte $00,$00,$00,$00,$04,$0C,$18,$38,$F0,$E0,$C0,$80,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$3C,$7F,$FF,$7F,$3F,$1E,$0C
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$80,$EF,$E7,$80,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$F7,$E7,$01,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$3C,$FE,$FF,$FE,$FC,$78,$30
  .byte $00,$00,$00,$00,$03,$07,$0F,$0F,$0F,$0F,$07,$03,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$C0,$E0,$F0,$F0,$F0,$F0,$E0,$C0,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$03,$06,$0C,$0B,$0C,$0F,$07,$03,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$C0,$E0,$B0,$20,$D0,$F0,$E0,$C0,$00,$00,$00,$00
  .byte $00,$00,$00,$0B,$0F,$0F,$0F,$07,$03,$03,$03,$03,$03,$03,$03,$03
  .byte $00,$00,$00,$40,$F0,$F0,$F0,$E0,$C0,$C0,$C0,$C0,$C0,$C0,$C0,$C0
  .byte $00,$24,$24,$6D,$7F,$7F,$3F,$3F,$1F,$0F,$0F,$0F,$0F,$0F,$0F,$0F
  .byte $00,$90,$90,$B0,$E0,$E0,$C0,$C0,$80,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$02,$01,$01,$02,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$40,$80,$80,$40,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$08,$04,$00,$00,$00,$00,$04,$08,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$10,$20,$00,$00,$00,$00,$20,$10,$00,$00,$00,$00,$00
  .byte $00,$20,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$20,$00
  .byte $00,$04,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$04,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$03,$03,$01,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$60,$C0,$E0,$C0,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$07,$00,$06,$0F,$00,$03,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$18,$F0,$00,$6C,$70,$E0,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$04,$00,$08,$00,$10,$28,$04,$00,$00,$02,$00,$00
  .byte $00,$00,$00,$00,$44,$10,$00,$00,$20,$02,$40,$08,$60,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00

; one-shot tone effects: period and volume for every frame
WH_TL:
  .byte $00,$C3,$FF,$70,$A1,$E1,$38,$68,$95,$1C,$23,$2F,$45,$59,$62,$6D
  .byte $7A,$8B,$A2,$C2,$F0,$2F,$2F,$2F,$24,$24,$24,$24,$24,$24,$2F,$2F
  .byte $2F,$24,$24,$24,$1B,$1B,$1B,$1B,$1B,$1B,$1B,$1B,$45,$45,$00,$00
  .byte $39,$39,$00,$00,$2E,$2E,$2E,$9C,$81,$6E,$60,$55,$4C,$45,$3F,$3A
  .byte $36,$32,$2F,$2C,$2A,$2A,$25,$21,$1E,$1C,$1A,$18,$16,$15,$14,$14
  .byte $15,$16,$17,$18,$1A,$1C,$1E,$21,$24,$27,$2C,$32,$39,$41,$A0,$41
  .byte $A0,$41,$A0,$41,$A0,$41,$A0,$41,$A0,$41,$A0,$41,$A0,$41,$A0,$41
  .byte $A0,$41,$A0,$41,$A0,$59,$5C,$60,$63,$67,$6B,$6F,$74,$7A,$7F,$86
  .byte $8D,$94,$9D,$A7,$B2,$BE,$CD,$DD,$F1,$09,$26,$4A,$78,$B4,$09,$78
  .byte $78,$78,$78,$5F,$5F,$5F,$5F,$50,$50,$50,$50,$3C,$3C,$3C,$3C,$3C
  .byte $3C,$3C,$3C,$3C,$3C,$3C,$3C,$50,$50,$50,$50,$3F,$3F,$3F,$3F,$35
  .byte $35,$35,$35,$28,$28,$28,$28,$20,$20,$20,$20,$20,$20,$20,$20,$20
  .byte $20,$20,$20,$20,$20,$28,$28,$28,$28,$28,$00,$00,$00,$28,$28,$28
  .byte $28,$28,$00,$00,$00,$1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
WH_TH:
  .byte $00,$00,$00,$01,$01,$01,$02,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$03,$02,$03
  .byte $02,$03,$02,$03,$02,$03,$02,$03,$02,$03,$02,$03,$02,$03,$02,$03
  .byte $02,$03,$02,$03,$02,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$01,$01,$01,$01,$02,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
WH_VOL:
  .byte $00,$0B,$0A,$08,$06,$04,$02,$06,$03,$0D,$0C,$0C,$0B,$0B,$0A,$09
  .byte $08,$06,$05,$04,$03,$0D,$0C,$0B,$0D,$0C,$0A,$09,$07,$06,$0D,$0C
  .byte $0B,$0D,$0C,$0B,$0D,$0C,$0B,$0A,$08,$07,$06,$05,$0A,$08,$00,$00
  .byte $0A,$08,$00,$00,$0A,$08,$05,$06,$06,$07,$07,$07,$08,$08,$08,$08
  .byte $09,$09,$09,$0A,$0A,$0C,$0C,$0C,$0C,$0C,$0D,$0D,$0D,$0D,$0D,$0D
  .byte $0C,$0C,$0B,$0A,$0A,$09,$08,$07,$07,$06,$05,$05,$04,$0C,$0C,$0C
  .byte $0C,$0B,$0B,$0B,$0B,$0A,$0A,$0A,$0A,$09,$09,$09,$09,$08,$08,$08
  .byte $08,$07,$07,$07,$07,$0D,$0D,$0C,$0C,$0B,$0B,$0A,$0A,$09,$09,$09
  .byte $08,$08,$07,$07,$06,$06,$06,$05,$05,$04,$04,$03,$03,$02,$02,$0B
  .byte $0A,$08,$07,$0B,$0A,$08,$07,$0B,$0A,$08,$07,$0B,$0B,$0A,$0A,$0A
  .byte $09,$09,$08,$08,$08,$07,$07,$0C,$0B,$09,$08,$0C,$0B,$09,$08,$0C
  .byte $0B,$09,$08,$0C,$0B,$09,$08,$0C,$0C,$0B,$0B,$0B,$0A,$0A,$0A,$0A
  .byte $09,$09,$09,$08,$08,$0D,$0C,$0B,$0A,$09,$00,$00,$00,$0D,$0C,$0B
  .byte $0A,$09,$00,$00,$00,$0D,$0C,$0A,$09,$08,$07,$05,$04
WH_START:
  .byte $00,$01,$07,$09,$15,$1E,$2C,$37,$45,$5D,$75,$8F,$A7,$C5
WH_LEN:
  .byte $00,$06,$02,$0C,$09,$0E,$0B,$0E,$18,$18,$1A,$18,$1E,$18
W_FLAP = 1
W_STEP = 2
W_JOUST = 3
W_EGG = 4
W_EGGAIR = 5
W_HATCH = 6
W_SPAWN = 7
W_PTERO = 8
W_TROLL = 9
W_DIE = 10
W_WAVE = 11
W_BONUS = 12
W_EXTRA = 13

; explosions: noise volume / period, low tone volume / period for every frame
EX_NV:
  .byte $00,$0E,$0E,$0D,$0C,$0C,$0B,$0A,$0A,$09,$08,$07,$07,$06,$05,$05
  .byte $04,$03,$03,$02,$01,$0E,$0E,$0E,$0E,$0D,$0D,$0D,$0D,$0C,$0C,$0C
  .byte $0C,$0B,$0B,$0B,$0B,$0A,$0A,$0A,$0A,$09,$09,$09,$09,$08,$08,$08
  .byte $08,$07,$07,$07,$07,$06,$06,$06,$06,$0F,$0F,$0F,$0F,$0E,$0E,$0E
  .byte $0E,$0D,$0D,$0D,$0D,$0C,$0C,$0C,$0C,$0B,$0B,$0B,$0B,$0A,$0A,$0A
  .byte $0A,$09,$09,$09,$09,$08,$08,$08,$08,$07,$07,$07,$07,$06,$06,$06
  .byte $06,$05,$05,$05,$05,$04,$04,$04,$04,$03,$03,$03,$03,$02,$02,$02
  .byte $02,$01,$01,$01,$01
EX_NP:
  .byte $00,$05,$05,$05,$05,$06,$06,$06,$06,$07,$07,$07,$07,$08,$08,$08
  .byte $08,$09,$09,$09,$09,$09,$09,$09,$09,$09,$09,$09,$09,$0A,$0A,$0A
  .byte $0A,$0A,$0A,$0A,$0A,$0B,$0B,$0B,$0B,$0B,$0B,$0B,$0B,$0C,$0C,$0C
  .byte $0C,$0C,$0C,$0C,$0C,$0D,$0D,$0D,$0D,$0E,$0E,$0E,$0E,$0E,$0E,$0E
  .byte $0E,$0F,$0F,$0F,$0F,$0F,$0F,$0F,$0F,$10,$10,$10,$10,$10,$10,$10
  .byte $10,$11,$11,$11,$11,$11,$11,$11,$11,$12,$12,$12,$12,$12,$12,$12
  .byte $12,$13,$13,$13,$13,$13,$13,$13,$13,$14,$14,$14,$14,$14,$14,$14
  .byte $14,$15,$15,$15,$15
EX_VC:
  .byte $00,$0A,$09,$08,$07,$06,$05,$04,$03,$02,$01,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$0B,$0B,$0B,$0B,$0A,$0A,$0A,$0A,$09,$09,$09
  .byte $09,$08,$08,$08,$08,$07,$07,$07,$07,$06,$06,$06,$06,$05,$05,$05
  .byte $05,$04,$04,$04,$04,$03,$03,$03,$03,$0D,$0D,$0D,$0D,$0C,$0C,$0C
  .byte $0C,$0B,$0B,$0B,$0B,$0A,$0A,$0A,$0A,$09,$09,$09,$09,$08,$08,$08
  .byte $08,$07,$07,$07,$07,$06,$06,$06,$06,$05,$05,$05,$05,$04,$04,$04
  .byte $04,$03,$03,$03,$03,$02,$02,$02,$02,$01,$01,$01,$01,$00,$00,$00
  .byte $00,$00,$00,$00,$00
EX_TL:
  .byte $00,$DF,$E7,$EF,$F7,$00,$0A,$15,$20,$2C,$3A,$49,$59,$6B,$7F,$96
  .byte $AF,$CC,$EC,$12,$3D,$B6,$BE,$C6,$CE,$D7,$DF,$E8,$F1,$FA,$04,$0D
  .byte $17,$21,$2C,$36,$41,$4D,$58,$64,$70,$7D,$8A,$97,$A5,$B3,$C2,$D1
  .byte $E0,$F0,$01,$12,$23,$36,$48,$5C,$70,$70,$70,$70,$70,$70,$70,$70
  .byte $70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70
  .byte $70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70
  .byte $70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70
  .byte $70,$70,$70,$70,$70
EX_TH:
  .byte $00,$00,$00,$00,$00,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
  .byte $01,$01,$01,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$03,$03
  .byte $03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03
  .byte $03,$03,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04
  .byte $04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04
  .byte $04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04
  .byte $04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04
  .byte $04,$04,$04,$04,$04
EX_START:
  .byte $00,$01,$15,$39
EX_LEN:
  .byte $00,$14,$24,$3C
S_SMALL = 1
S_LAVA = 2
S_SHIP = 3
S_BIG = S_SHIP
