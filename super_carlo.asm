;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;                                                              ;
;   SUPER CARLO  -  an original single-screen platform game    ;
;   65C02 assembly, TMS9918A Graphics II (tiles + sprites)     ;
;                                                              ;
;   - Carlo the welder (and his mate Fabio, 2 players at the   ;
;     same time) clears the decks of a cruise ship being built ;
;     in a shipyard: rats, riveter robots and gulls come in    ;
;     through the hatches at the top                           ;
;   - jump under a deck to bump it: whoever walks on it there  ;
;     turns over; touch him then to kick him into the sea. A   ;
;     riveter takes two bumps (the first one breaks its        ;
;     armour), a gull can be bumped only when it stands. If    ;
;     you wait, they get up again faster. Who reaches the      ;
;     drains at the bottom comes back from the top             ;
;   - the siren of the ship (bump it from below, 3 uses)       ;
;     turns over everybody who stands on a deck                ;
;   - welding sparks bounce across the ship, bolts fall from   ;
;     the crane, oil slicks make a deck slippery (2nd ship on) ;
;   - a ship: 6 decks and 2 bonus rounds (catch the bottles    ;
;     of the launch in 20 s), then it is launched and a faster ;
;     one begins                                               ;
;   - joystick LEFT / RIGHT = run, a button = jump. 1 player   ;
;     (both joysticks drive Carlo) or 2 at the same time       ;
;     (joystick 1 Carlo, joystick 2 Fabio)                     ;
;   - points: kick 800, 1600, 2400, 3200 in a row, spark or    ;
;     oil 500, bottle 800, all the bottles 5000, a deck with   ;
;     no life lost 1000; 3 lives each, one more at 20000       ;
;   - records: the 8 best scores, signed with 3 initials, kept ;
;     on the SD with the BIOS KEYB/SD (zone 30 of the save     ;
;     area, lib_records.asm)                                   ;
;   - SOUND (2 x AY-3-8910, played from the NMI at 60 Hz):     ;
;     tunes at the title, at every deck, at the launch;        ;
;     Carlo's sounds on the left, Fabio's on the right         ;
;   - the main loop writes the VDP only with the interrupt     ;
;     off (VDP_INT_OFF just after the NMI); the NMI only       ;
;     copies the SAT and plays the sound                       ;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; ---------------- zero page: game ----------------
NPL         = $30      ; number of players (1-2)
LIVES       = $32      ; 2 bytes: lives left to every player
SCL         = $34      ; 2 bytes: score per player (BCD): tens and units
SCM         = $36      ; thousands and hundreds
SCH         = $38      ; hundred thousands and ten thousands
HISC        = $3A      ; 3 bytes BCD (low, middle, high)
STAGE       = $40      ; stage of the ship 0-7 (3 and 7 = bonus rounds)
SHIP        = $41      ; ship 0, 1, ...
XGOT        = $42      ; 2 bytes: 1 = the extra life at 20000 was given
GSTATE      = $44      ; 0 playing, 1 the stage is over
GT          = $45      ; timer of GSTATE
NLEFT       = $46      ; enemies still to kick off the deck
QIDX        = $47      ; next enemy of the deck list to come out
SPAWNT      = $48      ; frames to the next enemy
SIDE        = $49      ; hatch of the next enemy (0 left, 1 right)
SIRENU      = $4A      ; uses of the siren left
DKTOT       = $4B      ; decks reached in the game (records)
BONUS       = $4C      ; 1 = bonus round
BTIME       = $4D      ; bonus round: seconds left
BTF         = $4E      ;              frames of the second
NBOT        = $4F      ;              bottles left
HUDD        = $50      ; to draw again: 1 scores, 2 lives, 4 bonus time
DKN         = $51      ; deck of the ship 0-5
SPARKT      = $52      ; frames to the next spark (0 = none yet)
BOLTT       = $53      ; frames to the next bolt
OILT        = $54      ; frames to the next oil slick
NOLOSS      = $55      ; 2 bytes: 1 = the player lost no life in this deck
DECKT       = $57      ; seconds in the deck
DECKF       = $58      ; frames of the second
BMR         = $59      ; 2 bumps at a time: deck row
BMC         = $5B      ;                    column
BMT         = $5D      ;                    frames left (0 = none)
SPDBASE     = $5F      ; speed level the enemies start with (the ship)
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
CI          = $72      ; player being handled (0 / 1)
OI          = $73      ; object being handled
FLIPT       = $74      ; frames an enemy stays turned over
HULLC       = $75      ; hull colour of the ship
JOYC        = $76      ; 2 bytes: the joystick of every player
JOYP        = $78      ; 2 bytes: the same, the frame before
HITC        = $7A      ; column of a head bump
HITR        = $7B      ; row of a head bump
P_JOY       = $80      ; 2 bytes (joystick, 1 = pressed)
PTS_L       = $82      ; points to add (BCD)
PTS_M       = $83
PTS_H       = $84
SATB        = $85      ; bytes of the SAT to copy
HOFF        = $86      ; name table of NT_XY and CLEAR_NT (always 0 here)
RR          = $87      ; first object in the SAT (turns)
LOSTN       = $88      ; lives lost (tests)
DEATH       = $89      ; what took the last life (kind, tests)
KICKS       = $8A      ; enemies kicked off (tests)
SIRDRW      = $8B      ; 1 = the siren to draw again

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

; ---------------- the players: one byte per player (0 Carlo, 1 Fabio) ----------------
P_X        = $0200       ; left x (wraps)
P_XF       = $0202
P_Y        = $0204       ; top y
P_YF       = $0206
P_VXL      = $0208       ; speeds 8.8 (signed)
P_VXH      = $020A
P_VYL      = $020C
P_VYH      = $020E
P_ST       = $0210       ; 0 out, 1 on a deck, 2 in the air, 3 hit (falls away), 4 waits to come back
P_DIR      = $0212       ; 0 right, 1 left
P_T        = $0214       ; timer
P_INV      = $0216       ; frames he cannot be hit (blinks)
P_RUN      = $0218       ; steps of the run (animation)
P_COMBO    = $021A       ; kicks in a row
P_CT       = $021C       ; frames the row stays open
P_JUMPQ    = $021E       ; 1 = jumped in this frame (sound)

; ---------------- objects: 12 slots, one byte per field ----------------
NOB        = 12
O_K        = $0240       ; kind (K_*, 0 = free)
O_X        = $024C
O_XF       = $0258
O_Y        = $0264
O_YF       = $0270
O_VXL      = $027C       ; speed 8.8 (signed)
O_VXH      = $0288
O_VYL      = $0294
O_VYH      = $02A0
O_S        = $02AC       ; state: 0 walks, 1 in the air, 2 turned over, 3 kicked
O_T        = $02B8       ; timer
O_LV       = $02C4       ; speed level 0-5
O_H        = $02D0       ; riveter: 1 = armour on
O_D        = $02DC       ; 0 right, 1 left

K_RAT      = 1
K_RIV      = 2
K_GULL     = 3
K_OIL      = 4
K_SPARK    = 5
K_BOLT     = 6
K_BOTTLE   = 7
K_PUFF     = 8

; ---------------- other RAM ----------------
MAP        = $0800       ; the name table (rows 0-23), for the collisions
SAT_BUFFER = $0600       ; 32 sprites x 4 + end of list
HUDBUF     = $06C0

; ---------------- parameters ----------------
BTN_MASK    = %00110000
JUMP_H      = $FC        ; jump: -3.625 pixels a frame
JUMP_L      = $60
GRAV        = $28        ; gravity: 0.156 pixels a frame each frame
RUN_MAX     = $01        ; run: 1.5 pixels a frame (8.8: $0180)
RUN_MAXL    = $80
FLOOR_Y     = 152        ; top y of who stands on the floor (row 21)
T_DECK      = 96         ; tiles: the plate, raised 2 (low, high), raised 4
T_SIREN     = 116

; ---------------- records on the SD (lib_records.asm) ----------------
REC_ZONE    = 30         ; fixed zone of the game in the save area
REC_RAM     = $7D00      ; $2A0 bytes after the program
REC_ROW     = 9          ; table on rows 9-17 of the title
REC_WIPEN   = 10         ; rows 9-18 of the title give way to the table
REC_JOY2    = 0          ; every player signs with his own joystick
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
  STZ SHIP
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
;  TITLE: the name, the crew, the enemies
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

; one frame of the title: the crew runs on the spot;
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
  LDA SATB                     ; the sprites are there: Carlo and Fabio run
  CMP #2
  BCC .tf_e
  LDA FRAME_CNT
  AND #8
  LSR A
  CLC
  ADC #PT_MANR1
  STA SAT_BUFFER+2
  STA SAT_BUFFER+6
.tf_e:
  JMP VDP_INT_ON


; ===============================================================
;  NEW GAME: ship 1, deck 1, 3 lives each
; ===============================================================
NEW_GAME:
  LDX #$01
.ng_p:
  STZ SCL,X
  STZ SCM,X
  STZ SCH,X
  STZ LIVES,X
  STZ XGOT,X
  STZ P_ST,X
  DEX
  BPL .ng_p
  LDA #3
  STA LIVES
  LDA NPL
  CMP #2
  BNE .ng_1
  LDA #3
  STA LIVES+1
.ng_1:
  STZ STAGE
  STZ SHIP
  STZ LOSTN
  STZ KICKS
  STZ DKTOT
  STZ RR
  ; fall into STAGE_START


; ===============================================================
;  A STAGE: a deck or a bonus round
; ===============================================================
STAGE_START:
  LDX #$FF
  TXS
  JSR HIDE_SPRITES
  JSR VDP_INT_OFF
  LDA #$82                     ; display off while the ship is drawn
  STA VREG
  LDA #(VDP_REGISTER_BITS | 1)
  STA VREG
  LDA SHIP                     ; the hull of this ship
  AND #3
  TAX
  LDA HULLS,X
  STA HULLC
  JSR LOAD_COLS
  STZ BONUS
  LDA STAGE                    ; stages 3 and 7: bonus rounds; the others: decks 0-5
  CMP #3
  BEQ .st_b
  CMP #7
  BNE .st_d
.st_b:
  INC BONUS
  BRA .st_s
.st_d:
  CMP #3
  BCC .st_k
  DEC A
.st_k:
  STA DKN
  LDA DKTOT
  CMP #99
  BCS .st_s
  INC DKTOT
.st_s:
  LDA STAGE                    ; the siren: 3 uses again at decks 1 and 4
  BEQ .st_si
  CMP #4
  BNE .st_sn
.st_si:
  LDA #3
  STA SIRENU
.st_sn:
  JSR DRAW_SHIP
  JSR DRAW_HUD
  JSR STAGE_INIT
  JSR MSG_STAGE
  JSR BUILD_SAT
  JSR VDP_INT_ON               ; (display on)
  LDA #1                       ; the tune of a new deck
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
  LDA #20
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
  JSR BUMPS_DRAW               ; the plates going up and down
  JSR READ_JOY
  JSR NEXT_RND
  LDA NPL                      ; the joysticks: 1 player = both drive Carlo
  CMP #2
  BEQ .gl_2
  LDA P_JOY
  ORA P_JOY+1
  STA JOYC
  STZ JOYC+1
  BRA .gl_j
.gl_2:
  LDA P_JOY
  STA JOYC
  LDA P_JOY+1
  STA JOYC+1
.gl_j:
  JSR PLAYERS
  JSR OBJECTS
  JSR SPAWNS
  JSR TOUCHES
  JSR CLOCK
  JSR UPDATE_HUD
  JSR BUILD_SAT
WEND:
  JSR VDP_INT_ON
  LDA JOYC
  STA JOYP
  LDA JOYC+1
  STA JOYP+1
  LDA P_ST                     ; nobody left: game over
  ORA P_ST+1
  BEQ .gl_go
  LDA GSTATE
  BEQ GAME_LOOP
  DEC GT
  BNE GAME_LOOP
  JMP STAGE_CLEAR
.gl_go:
  JMP GAME_OVER


; ===============================================================
;  THE STAGE IS OVER: bonuses, the next stage, the launch
; ===============================================================
STAGE_CLEAR:
  JSR HIDE_SPRITES
  LDA #2
  STA SONG
  LDA #CMD_START
  STA SND_CMD
  JSR VDP_INT_OFF
  LDA BONUS
  BEQ .sc_dk
  LDA NBOT                     ; bonus round: all the bottles?
  BNE .sc_w
  LDA #<TXT_ALLB
  STA TP
  LDA #>TXT_ALLB
  STA TP+1
  JSR PRINT
  LDX #1
.sc_ab:
  LDA P_ST,X                   ; 5000 to every player still in the game
  BEQ .sc_an
  STX CI
  LDA #$00
  LDY #$50
  JSR ADD_PTS_CI
  LDX CI
.sc_an:
  DEX
  BPL .sc_ab
  BRA .sc_w
.sc_dk:
  LDA #<TXT_CLEAR
  STA TP
  LDA #>TXT_CLEAR
  STA TP+1
  JSR PRINT
  LDX #1                       ; no life lost in the deck: 1000
.sc_nl:
  LDA P_ST,X
  BEQ .sc_nn
  LDA NOLOSS,X
  BEQ .sc_nn
  STX CI
  LDA #$00
  LDY #$10
  JSR ADD_PTS_CI
  LDX CI
.sc_nn:
  DEX
  BPL .sc_nl
.sc_w:
  JSR UPDATE_HUD
  JSR VDP_INT_ON
.sc_t:
  LDA #1
  JSR WAIT_FRAMES
  LDA SND_BUSY
  BNE .sc_t
  LDA #60
  JSR WAIT_FRAMES
  INC STAGE                    ; the next stage; after the eighth, the launch
  LDA STAGE
  CMP #8
  BCC .sc_n
  STZ STAGE
  JSR LAUNCH
.sc_n:
  JMP STAGE_START

; the ship is ready: the launch tune, a faster ship
LAUNCH:
  JSR VDP_INT_OFF
  JSR MSG_CLEAR
  LDA #<TXT_LAUNCH
  STA TP
  LDA #>TXT_LAUNCH
  STA TP+1
  JSR PRINT
  JSR VDP_INT_ON
  LDA #3
  STA SONG
  LDA #CMD_START
  STA SND_CMD
  LDA #20
  JSR WAIT_FRAMES
.la_t:
  LDA #1
  JSR WAIT_FRAMES
  LDA SND_BUSY
  BNE .la_t
  LDA #60
  JSR WAIT_FRAMES
  LDA SHIP
  CMP #9
  BCS .la_r
  INC SHIP
.la_r:
  RTS

GAME_OVER:
  LDA #W_OVER
  LDX #2
  JSR SFX_WHISTLE
  JSR VDP_INT_OFF
  JSR HIDE_SPRITES
  JSR MSG_CLEAR
  LDA #<TXT_OVER
  STA TP
  LDA #>TXT_OVER
  STA TP+1
  JSR PRINT
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
  LDA DKTOT                    ; extra byte: the decks reached
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
REC_NAME:  .byte "SUPER CARLO     "
REC_HEAD:  .byte "BEST CREWS",0
REC_XLBL:  .byte "DECK ",0


; ===============================================================
;  SCREEN OF THE SHIP, MESSAGES
; ===============================================================
; the name table: rows 2-22 from SCREEN (and MAP), rows 0-1 and 23 empty (interrupt off)
DRAW_SHIP:
  LDA #<SCREEN
  STA PTR
  LDA #>SCREEN
  STA PTR+1
  LDA #<(MAP+64)
  STA PTR2
  LDA #>(MAP+64)
  STA PTR2+1
  LDX #3                       ; 672 bytes: 2 pages and 160
  LDY #0
.ds_c:
  LDA (PTR),Y
  STA (PTR2),Y
  INY
  BNE .ds_c
  INC PTR+1
  INC PTR2+1
  DEX
  BNE .ds_c
  LDX #63                      ; (3 pages copied: rows 0-1 and 23 to spaces after)
.ds_b:
  LDA #$20
  STA MAP,X
  CPX #32
  BCS .ds_n
  STA MAP+$2E0,X
.ds_n:
  DEX
  BPL .ds_b
  JSR SIREN_MAP                ; the siren as many uses as are left
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
.ds_v:
  LDA (PTR),Y
  STA VDATA
  INY
  BNE .ds_v
  INC PTR+1
  DEX
  BNE .ds_v
  RTS

; the siren tiles in MAP for SIRENU uses (0 = gone)
SIREN_MAP:
  LDA SIRENU
  BEQ .sm_0
  ASL A
  CLC
  ADC #T_SIREN
  STA MAP+17*32+15
  INC A
  STA MAP+17*32+16
  LDA #T_SIREN
  STA MAP+16*32+15
  INC A
  STA MAP+16*32+16
  RTS
.sm_0:
  STZ MAP+16*32+15
  STZ MAP+16*32+16
  STZ MAP+17*32+15
  STZ MAP+17*32+16
  RTS

; X = row: the row of MAP to the name table again (interrupt off)
PUT_MAPROW:
  PHX
  LDY #0
  JSR NT_XY
  PLA
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
  LDY #0
.pm_c:
  LDA (PTR),Y
  STA VDATA
  INY
  CPY #32
  BNE .pm_c
  RTS

; the message of the stage on rows 8 and 13
MSG_STAGE:
  LDA BONUS
  BEQ .ms_d
  LDA #<TXT_BONUSR
  STA TP
  LDA #>TXT_BONUSR
  STA TP+1
  JMP PRINT
.ms_d:
  LDA #<TXT_DECK
  STA TP
  LDA #>TXT_DECK
  STA TP+1
  JSR PRINT
  LDA DKN
  INC A
  ORA #$30
  STA VDATA
  LDX #13                      ; the name of the deck
  LDY #8
  JSR NT_XY
  LDA DKN
  ASL A
  ASL A
  ASL A
  ASL A
  TAX
  LDY #16
.ms_n:
  LDA DECK_TXT,X
  STA VDATA
  INX
  DEY
  BNE .ms_n
  RTS

; the rows of the messages back to the ship
MSG_CLEAR:
  LDX #8
  JSR PUT_MAPROW
  LDX #9
  JSR PUT_MAPROW
  LDX #13
  JMP PUT_MAPROW


; ===============================================================
;  HUD: rows 0-1 (names, scores, lives, record), row 23 (ship,
;  deck, bonus time)
; ===============================================================
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

; X = player: his lives on row 1 (5 places, a helmet each)
DRAW_LIVES:
  PHX
  LDY LV_COL,X
  LDX #1
  JSR NT_XY
  PLX
  LDA LIVES,X
  STA T0
  LDY #0
.dl_l:
  LDA #$20
  CPY T0
  BCS .dl_w
  LDA #124
.dl_w:
  STA VDATA
  INY
  CPY #5
  BNE .dl_l
  RTS

; row 23: SHIP n  DECK n  name / BONUS ROUND  TIME nn
DRAW_BOT:
  LDX #23
  LDY #0
  JSR NT_XY
  LDX #0
.db_s:
  LDA TXT_SHIP,X
  STA VDATA
  INX
  CPX #5
  BNE .db_s
  LDA SHIP
  INC A
  JSR PUT_NUM
  LDX #23
  LDY #8
  JSR NT_XY
  LDA BONUS
  BNE .db_b
  LDX #0
.db_d:
  LDA TXT_DECKH,X
  STA VDATA
  INX
  CPX #5
  BNE .db_d
  LDA DKN
  INC A
  ORA #$30
  STA VDATA
  LDX #23
  LDY #15
  JSR NT_XY
  LDA DKN
  ASL A
  ASL A
  ASL A
  ASL A
  TAX
  LDY #16
.db_n:
  LDA DECK_TXT,X
  STA VDATA
  INX
  DEY
  BNE .db_n
  RTS
.db_b:
  LDX #0
.db_bt:
  LDA TXT_BTIME,X
  STA VDATA
  INX
  CPX #11
  BNE .db_bt
  ; fall into DRAW_BTIME
DRAW_BTIME:
  LDX #23
  LDY #19
  JSR NT_XY
  LDA BTIME
  JSR BIN2BCD
  JMP PUT_2

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
  LDX #0
  JSR DRAW_LIVES
  LDA NPL
  CMP #2
  BNE .dh_b
  LDX #1
  JSR DRAW_LIVES
.dh_b:
  JMP DRAW_BOT

UPDATE_HUD:                    ; HUDD bits: 1 scores, 2 lives, 4 bonus time
  LDA HUDD
  BEQ .uh_r
  STZ HUDD
  PHA
  AND #1
  BEQ .uh_l
  LDX #0
  JSR DRAW_SCORE
  LDA NPL
  CMP #2
  BNE .uh_l
  LDX #1
  JSR DRAW_SCORE
.uh_l:
  PLA
  PHA
  AND #2
  BEQ .uh_t
  LDX #0
  JSR DRAW_LIVES
  LDA NPL
  CMP #2
  BNE .uh_t
  LDX #1
  JSR DRAW_LIVES
.uh_t:
  PLA
  AND #4
  BEQ .uh_r
  JSR DRAW_BTIME
.uh_r:
  RTS


; ===============================================================
;  SCORE
; ===============================================================
; A = points (BCD tens and units), Y = hundreds and thousands, to player CI
ADD_PTS_CI:
  STA PTS_L
  STY PTS_M
  STZ PTS_H
  ; fall into ADD_SCORE

; PTS_L / PTS_M / PTS_H (BCD) to the player CI; a life more at 20000
ADD_SCORE:
  PHX
  PHY
  LDX CI
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
  LDA XGOT,X
  BNE .as_d
  LDA SCH,X
  CMP #$02
  BCC .as_d
  INC XGOT,X
  LDA LIVES,X
  CMP #5
  BCS .as_m
  INC LIVES,X
.as_m:
  LDA #2
  TSB HUDD
  LDA #W_EXTRA
  JSR SFX_P
.as_d:
  LDA #1
  TSB HUDD
  PLY
  PLX
  RTS

; A = whistle of player CI: Carlo on the left chip, Fabio on the right (keeps X, Y)
SFX_P:
  PHX
  LDX CI
  JSR SFX_WHISTLE
  PLX
  RTS


; ===============================================================
;  THE STAGE: players, enemies to come, timers
; ===============================================================
STAGE_INIT:
  LDX #NOB-1
.si_o:
  STZ O_K,X
  DEX
  BPL .si_o
  STZ BMT
  STZ BMT+1
  STZ QIDX
  STZ SIDE
  STZ DECKT
  STZ DECKF
  LDA #60
  STA SPAWNT
  LDA #20                      ; seconds to the first spark, bolt, oil slick
  STA SPARKT
  LDA #8
  STA BOLTT
  LDA #12
  STA OILT
  LDA SHIP                     ; the ship: faster enemies, shorter stun
  CMP #3
  BCC .si_b
  LDA #3
.si_b:
  STA SPDBASE
  ASL A
  ASL A
  ASL A
  ASL A
  ASL A
  STA T0
  LDA #255
  SEC
  SBC T0
  STA FLIPT
  STZ NLEFT
  LDA BONUS
  BNE .si_bo
  LDX DKN
  LDA DK_N,X
  STA NLEFT
  BRA .si_p
.si_bo:
  LDA #20                      ; bonus round: 20 s, the bottles
  STA BTIME
  LDA #60
  STA BTF
  LDA #NBOTTLES
  STA NBOT
  LDY #NBOTTLES-1
.si_bt:
  PHY
  LDA BOT_X,Y
  STA T2
  LDA BOT_Y,Y
  STA T3
  LDA #K_BOTTLE
  JSR NEW_OBJ
  PLY
  DEY
  BPL .si_bt
.si_p:
  LDX #1                       ; the players with lives left: on the floor
.si_pl:
  STZ P_ST,X
  LDA LIVES,X
  BEQ .si_pn
  LDA #1
  STA P_ST,X
  STA NOLOSS,X
  LDA START_X,X
  STA P_X,X
  LDA #FLOOR_Y
  STA P_Y,X
  STZ P_XF,X
  STZ P_YF,X
  STZ P_VXL,X
  STZ P_VXH,X
  STZ P_VYL,X
  STZ P_VYH,X
  STZ P_INV,X
  STZ P_COMBO,X
  STZ P_CT,X
  TXA
  STA P_DIR,X                  ; Carlo looks right, Fabio left
.si_pn:
  DEX
  BPL .si_pl
  RTS

; the clock: deck seconds, the hazards, the bonus time, the end of the stage
CLOCK:
  LDA GSTATE
  BNE .ck_r
  LDA BONUS
  BEQ .ck_d
  LDA NBOT                     ; bonus round: all the bottles or the time is up
  BEQ .ck_end
  DEC BTF
  BNE .ck_r
  LDA #60
  STA BTF
  LDA #4
  TSB HUDD
  DEC BTIME
  BNE .ck_r
.ck_end:
  LDA #1
  STA GSTATE
  LDA #40
  STA GT
.ck_r:
  RTS
.ck_d:
  LDA NLEFT                    ; a deck: every enemy kicked off
  BNE .ck_s
  LDA #1
  STA GSTATE
  LDA #90
  STA GT
  RTS
.ck_s:
  DEC DECKF
  BPL .ck_r
  LDA #59
  STA DECKF
  INC DECKT
  DEC SPARKT                   ; ---- once a second: the hazards
  BNE .ck_b
  LDA #12
  LDX SHIP
  BEQ .ck_sp
  LDA #8
.ck_sp:
  STA SPARKT
  JSR NEW_SPARK
.ck_b:
  LDA STAGE                    ; bolts from the third deck (or the second ship)
  CMP #2
  BCS .ck_bo
  LDA SHIP
  BEQ .ck_o
.ck_bo:
  DEC BOLTT
  BNE .ck_o
  LDA #9
  STA BOLTT
  JSR NEW_BOLT
.ck_o:
  LDA SHIP                     ; oil slicks from the second ship
  BEQ .ck_x
  DEC OILT
  BNE .ck_x
  LDA #20
  STA OILT
  JSR NEW_OIL
.ck_x:
  RTS


; ===============================================================
;  THE PLAYERS
; ===============================================================
PLAYERS:
  LDX #1
.pl_l:
  STX CI
  LDA P_ST,X
  BEQ .pl_n
  CMP #3
  BCC .pl_m
  BEQ .pl_hit
  DEC P_T,X                    ; waiting: back from the top
  BNE .pl_n
  JSR RESPAWN
  BRA .pl_n
.pl_hit:
  JSR FALL_AWAY
  BRA .pl_n
.pl_m:
  JSR MOVE_PLAYER
.pl_n:
  LDX CI
  LDA P_INV,X
  BEQ .pl_c
  DEC P_INV,X
.pl_c:
  LDA P_CT,X                   ; the row of kicks closes
  BEQ .pl_x
  DEC P_CT,X
  BNE .pl_x
  STZ P_COMBO,X
.pl_x:
  DEX
  BPL .pl_l
  JMP PUSH_APART

; hit: up a little, then down out of the screen
FALL_AWAY:
  CLC
  LDA P_VYL,X
  ADC #GRAV
  STA P_VYL,X
  LDA P_VYH,X
  ADC #0
  STA P_VYH,X
  CLC
  LDA P_YF,X
  ADC P_VYL,X
  STA P_YF,X
  LDA P_Y,X
  ADC P_VYH,X
  STA P_Y,X
  CMP #200
  BCC .fa_r
  CMP #240
  BCS .fa_r
  LDA LIVES,X                  ; down: back later, or out of the game
  BEQ .fa_out
  LDA #4
  STA P_ST,X
  LDA #60
  STA P_T,X
  RTS
.fa_out:
  STZ P_ST,X
.fa_r:
  RTS

; from the top of the ship, over the top deck, blinking
RESPAWN:
  LDA #2
  STA P_ST,X
  LDA RESP_X,X
  STA P_X,X
  LDA #16
  STA P_Y,X
  STZ P_XF,X
  STZ P_YF,X
  STZ P_VXL,X
  STZ P_VXH,X
  STZ P_VYL,X
  STZ P_VYH,X
  LDA #180
  STA P_INV,X
  RTS

; X = player on a deck or in the air
MOVE_PLAYER:
  JSR RUN_X
  CLC                          ; ---- x moves (the screen wraps by itself)
  LDA P_XF,X
  ADC P_VXL,X
  STA P_XF,X
  LDA P_X,X
  ADC P_VXH,X
  STA P_X,X
  LDA P_ST,X                   ; ---- on a deck: jump, or walk off its end
  CMP #1
  BNE .mp_air
  LDA JOYC,X
  AND #BTN_MASK
  BEQ .mp_sup
  LDA JOYP,X
  AND #BTN_MASK
  BNE .mp_sup
  LDA #JUMP_L
  STA P_VYL,X
  LDA #JUMP_H
  STA P_VYH,X
  LDA #2
  STA P_ST,X
  LDA #W_JUMP
  JSR SFX_P
  BRA .mp_air
.mp_sup:
  LDA P_X,X                    ; still something under the feet?
  LDY P_Y,X
  JSR SUPPORT
  BCS .mp_r
  LDA #2
  STA P_ST,X
  STZ P_VYL,X
  STZ P_VYH,X
.mp_r:
  RTS
.mp_air:                       ; ---- in the air: gravity, head and feet against the decks
  CLC
  LDA P_VYL,X
  ADC #GRAV
  STA P_VYL,X
  LDA P_VYH,X
  ADC #0
  CMP #4                       ; falls at most 4 pixels a frame
  BMI .mp_vy
  LDA #4
  STZ P_VYL,X
.mp_vy:
  STA P_VYH,X
  CLC
  LDA P_YF,X
  ADC P_VYL,X
  STA P_YF,X
  LDA P_Y,X
  ADC P_VYH,X
  STA P_Y,X
  LDA P_VYH,X
  BPL .mp_down
  LDA P_Y,X                    ; going up: the top of the screen, the head
  CMP #16
  BCS .mp_hd
  LDA #16
  STA P_Y,X
  STZ P_VYL,X
  STZ P_VYH,X
  RTS
.mp_hd:
  LDA P_X,X
  CLC
  ADC #8
  LSR A
  LSR A
  LSR A
  STA HITC
  LDA P_Y,X
  LSR A
  LSR A
  LSR A
  STA HITR
  JSR TILE_AT
  JSR IS_SOLID
  BCC .mp_r2
  LDA HITR                     ; the head hit a plate: back below it, bump it
  ASL A
  ASL A
  ASL A
  CLC
  ADC #8
  STA P_Y,X
  LDA #$40
  STA P_VYL,X
  STZ P_VYH,X
  JMP HEAD_HIT
.mp_down:
  LDA P_X,X                    ; coming down: the feet on a deck
  LDY P_Y,X
  JSR LANDING
  BCC .mp_r2
  STA P_Y,X
  STZ P_YF,X
  STZ P_VYL,X
  STZ P_VYH,X
  LDA #1
  STA P_ST,X
.mp_r2:
  RTS

; X = player: the run speed, towards the joystick or slowing down
RUN_X:
  LDA JOYC,X                   ; ---- run: towards the joystick, else slow down
  AND #$0C
  BEQ .rx_slow
  CMP #$08
  BNE .rx_left
  STZ P_DIR,X
  LDA P_ST,X
  CMP #1
  LDA #$20
  BEQ .rx_ar
  LDA #$10
.rx_ar:
  CLC
  ADC P_VXL,X
  STA P_VXL,X
  LDA P_VXH,X
  ADC #0
  STA P_VXH,X
  BMI .rx_r1
  CMP #RUN_MAX                 ; at most +1.5
  BCC .rx_r1
  LDA P_VXL,X
  CMP #RUN_MAXL
  BCC .rx_r1
  LDA #RUN_MAXL
  STA P_VXL,X
  LDA #RUN_MAX
  STA P_VXH,X
.rx_r1:
  RTS
.rx_left:
  LDA #1
  STA P_DIR,X
  LDA P_ST,X
  CMP #1
  LDA #$20
  BEQ .rx_al
  LDA #$10
.rx_al:
  STA T0
  LDA P_VXL,X
  SEC
  SBC T0
  STA P_VXL,X
  LDA P_VXH,X
  SBC #0
  STA P_VXH,X
  BPL .rx_r2
  CMP #$FE                     ; at most -1.5 ($FE80)
  BCC .rx_lc
  BNE .rx_r2
  LDA P_VXL,X
  CMP #$80
  BCS .rx_r2
.rx_lc:
  LDA #$80
  STA P_VXL,X
  LDA #$FE
  STA P_VXH,X
.rx_r2:
  RTS
.rx_slow:
  LDA P_ST,X                   ; in the air the speed stays
  CMP #1
  BNE .rx_r
  JSR SLIPPERY                 ; A = how much it slows down
  STA T0
  LDA P_VXH,X
  BMI .rx_sn
  ORA P_VXL,X
  BEQ .rx_r
  LDA P_VXL,X
  SEC
  SBC T0
  STA P_VXL,X
  LDA P_VXH,X
  SBC #0
  STA P_VXH,X
  BPL .rx_r
  STZ P_VXL,X
  STZ P_VXH,X
  BRA .rx_r
.rx_sn:
  LDA P_VXL,X
  CLC
  ADC T0
  STA P_VXL,X
  LDA P_VXH,X
  ADC #0
  STA P_VXH,X
  BMI .rx_r
  STZ P_VXL,X
  STZ P_VXH,X
.rx_r:
  RTS

; A = how much a player on a deck slows down: less on the deck of an oil slick
SLIPPERY:
  LDY #NOB-1
.sl_l:
  LDA O_K,Y
  CMP #K_OIL
  BNE .sl_n
  LDA O_Y,Y
  CMP P_Y,X
  BNE .sl_n
  LDA #$04
  RTS
.sl_n:
  DEY
  BPL .sl_l
  LDA #$20
  RTS

; the players push each other apart
PUSH_APART:
  LDA P_ST
  CMP #1
  BCC .pa_r
  CMP #3
  BCS .pa_r
  LDA P_ST+1
  CMP #1
  BCC .pa_r
  CMP #3
  BCS .pa_r
  LDA P_Y
  SEC
  SBC P_Y+1
  CLC
  ADC #12
  CMP #24
  BCS .pa_r
  LDA P_X
  SEC
  SBC P_X+1
  CLC
  ADC #12
  CMP #24
  BCS .pa_r
  CMP #12                      ; Carlo on the right of Fabio: Carlo right, Fabio left
  LDX #0
  BCS .pa_s
  INX
.pa_s:
  LDA #$00
  STA P_VXL,X
  LDA #$01
  STA P_VXH,X
  INC P_X,X
  TXA
  EOR #1
  TAX
  LDA #$00
  STA P_VXL,X
  LDA #$FF
  STA P_VXH,X
  DEC P_X,X
.pa_r:
  RTS


; ===============================================================
;  THE DECKS: collisions with the tiles
; ===============================================================
; HITR / HITC: A = the tile of MAP there
TILE_AT:
  LDA HITR
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
  LDY HITC
  LDA (PTR),Y
  RTS

; A = tile: C = 1 if it is solid (a plate, raised or not, or the siren)
IS_SOLID:
  CMP #T_DECK
  BCC .is_n
  CMP #T_DECK+5
  BCC .is_y
  CMP #T_SIREN
  BCC .is_n
  CMP #T_SIREN+8
  BCC .is_y
.is_n:
  CLC
  RTS
.is_y:
  SEC
  RTS

; A = left x, Y = top y of a 16x16 body standing: C = 1 if a plate is under its feet
; (columns of x + 4 and x + 11, the row of y + 16) (keeps X)
SUPPORT:
  STA T6
  TYA
  CLC
  ADC #16
  CMP #192
  BCS .su_n
  LSR A
  LSR A
  LSR A
  STA HITR
  LDA T6
  CLC
  ADC #4
  LSR A
  LSR A
  LSR A
  STA HITC
  JSR TILE_AT
  JSR IS_SOLID
  BCS .su_r
  LDA T6
  CLC
  ADC #11
  LSR A
  LSR A
  LSR A
  STA HITC
  JSR TILE_AT
  JMP IS_SOLID
.su_n:
  CLC
.su_r:
  RTS

; A = left x, Y = top y of a falling body: C = 1 if its feet just went into the top
; of a plate; then A = the top y standing on it (keeps X)
LANDING:
  STA T6
  TYA
  CLC
  ADC #16
  CMP #192
  BCS .ln_n
  STA T7
  AND #7
  CMP #5
  BCS .ln_n
  LDY T6
  LDA T7
  TAY
  LDA T6
  JSR SUPPORT_F
  BCC .ln_r
  LDA T7
  AND #$F8
  SEC
  SBC #16
  SEC
  RTS
.ln_n:
  CLC
.ln_r:
  RTS

; A = left x, Y = feet y: C = 1 if a plate is at the feet (keeps X)
SUPPORT_F:
  STA T6
  TYA
  LSR A
  LSR A
  LSR A
  STA HITR
  LDA T6
  CLC
  ADC #4
  LSR A
  LSR A
  LSR A
  STA HITC
  JSR TILE_AT
  JSR IS_SOLID
  BCS .sf_r
  LDA T6
  CLC
  ADC #11
  LSR A
  LSR A
  LSR A
  STA HITC
  JSR TILE_AT
  JMP IS_SOLID
.sf_r:
  RTS


; ===============================================================
;  BUMPS: a head under a plate (player CI, HITR / HITC)
; ===============================================================
HEAD_HIT:
  LDA HITR                     ; the siren?
  CMP #16
  BCC .hh_d
  LDA HITC
  CMP #15
  BCC .hh_d
  CMP #17
  BCS .hh_d
  JMP SIREN_HIT
.hh_d:
  LDA HITR                     ; the floor cannot be bumped
  CMP #21
  BCC .hh_ok
  RTS
.hh_ok:
  LDY #0                       ; a free slot for the plates going up
  LDA BMT
  BEQ .hh_s
  INY
  LDA BMT+1
  BEQ .hh_s
  LDY #0
.hh_s:
  LDA HITR
  STA BMR,Y
  LDA HITC
  STA BMC,Y
  LDA #17
  STA BMT,Y
  LDA #S_BUMP
  LDX CI
  LDY P_X,X
  JSR BOOM_AT
  LDA HITR                     ; what stands on the plate there (T0 = top of the deck,
  ASL A                        ; T1 = middle of the bump)
  ASL A
  ASL A
  STA T0
  LDA HITC
  ASL A
  ASL A
  ASL A
  ORA #4
  STA T1
  LDX #NOB-1
.hh_o:
  LDA O_K,X
  BEQ .hh_on
  CMP #K_SPARK
  BEQ .hh_sp
  CMP #K_SPARK
  BCS .hh_on
  LDA O_S,X                    ; an enemy on the plate, near the bump
  CMP #3
  BCS .hh_on
  CMP #1
  BEQ .hh_on
  LDA O_Y,X
  CLC
  ADC #16
  CMP T0
  BNE .hh_on
  JSR NEAR_T1
  BCS .hh_on
  JSR BUMP_ENEMY
  BRA .hh_on
.hh_sp:                        ; a spark just above the plate: out
  JSR NEAR_T1
  BCS .hh_on
  LDA O_Y,X
  CLC
  ADC #16
  SEC
  SBC T0
  CLC
  ADC #20
  CMP #24
  BCS .hh_on
  JSR SPARK_OUT
.hh_on:
  DEX
  BPL .hh_o
  LDX CI                       ; the other player standing there jumps up
  TXA
  EOR #1
  TAX
  LDA P_ST,X
  CMP #1
  BNE .hh_r
  LDA P_Y,X
  CLC
  ADC #16
  CMP T0
  BNE .hh_r
  LDA P_X,X
  CLC
  ADC #8
  SEC
  SBC T1
  CLC
  ADC #14
  CMP #28
  BCS .hh_r
  LDA #2
  STA P_ST,X
  STZ P_VYL,X
  LDA #$FE
  STA P_VYH,X
.hh_r:
  LDX CI
  RTS

; X = object: C = 0 if its middle is within 14 pixels of T1
NEAR_T1:
  LDA O_X,X
  CLC
  ADC #8
  SEC
  SBC T1
  CLC
  ADC #14
  CMP #28
  RTS

; X = enemy standing on a bumped plate (or anywhere: the siren)
BUMP_ENEMY:
  LDA O_K,X
  CMP #K_OIL
  BNE .be_e
  LDA #$00                     ; an oil slick: gone, 500
  LDY #$05
  JSR PTS_CI_X
  JMP TO_PUFF
.be_e:
  LDA O_S,X
  CMP #2
  BNE .be_up
  STZ O_S,X                    ; turned over: back on its feet, with a hop
  BRA .be_hop
.be_up:
  LDA O_K,X
  CMP #K_RIV
  BNE .be_f
  LDA O_H,X                    ; a riveter: the first bump breaks the armour
  BEQ .be_f
  STZ O_H,X
  INC O_LV,X
  BRA .be_hop
.be_f:
  LDA #2                       ; turned over
  STA O_S,X
  LDA FLIPT
  STA O_T,X
  STZ O_VXL,X
  STZ O_VXH,X
  STZ O_VYL,X
  STZ O_VYH,X
  RTS
.be_hop:
  LDA #1
  STA O_S,X
  LDA #$FE
  STA O_VYH,X
  STZ O_VYL,X
  RTS

; A / Y = points (BCD) to the player CI (keeps X)
PTS_CI_X:
  PHX
  JSR ADD_PTS_CI
  PLX
  RTS

; the siren: every enemy on a deck is bumped
SIREN_HIT:
  LDA SIRENU
  BEQ .sh_r
  DEC SIRENU
  LDA #W_SIREN
  LDX #2
  JSR SFX_WHISTLE
  LDX #NOB-1
.sh_o:
  LDA O_K,X
  BEQ .sh_n
  CMP #K_SPARK
  BCS .sh_n
  LDA O_S,X
  CMP #1
  BEQ .sh_n
  CMP #3
  BCS .sh_n
  JSR BUMP_ENEMY
.sh_n:
  DEX
  BPL .sh_o
  JSR SIREN_MAP                ; one lamp less (none: the siren is gone)
  LDA #1
  STA SIRDRW
.sh_r:
  LDX CI
  RTS

; every frame (VDP interrupt off): the plates of the bumps, the siren
BUMPS_DRAW:
  LDA SIRDRW
  BEQ .bd_b
  STZ SIRDRW
  LDX #16
  JSR PUT_MAPROW
  LDX #17
  JSR PUT_MAPROW
.bd_b:
  LDX #1
.bd_l:
  LDA BMT,X
  BEQ .bd_n
  DEC BMT,X
  LDA BMT,X
  LDY #T_DECK+1                ; 16: up 2, 12: up 4, 4: up 2, 0: down
  CMP #16
  BEQ .bd_w
  LDY #T_DECK+3
  CMP #12
  BEQ .bd_w
  LDY #T_DECK+1
  CMP #4
  BEQ .bd_w
  LDY #0
  CMP #0
  BNE .bd_n
.bd_w:
  STY T4                       ; the low tile (0 = the plate again)
  STX T5
  LDA BMC,X
  DEC A
  AND #31
  STA T3
  LDA #3
  STA T2
.bd_c:
  JSR BUMP_COL
  LDA T3
  INC A
  AND #31
  STA T3
  DEC T2
  BNE .bd_c
  LDX T5
.bd_n:
  DEX
  BPL .bd_l
  RTS

; column T3 of the bump T5: the plate tile T4 (0 = as in MAP) and the tile above
BUMP_COL:
  LDX T5
  LDA BMR,X
  STA HITR
  LDA T3
  STA HITC
  JSR TILE_AT
  CMP #T_DECK                  ; only where the deck is
  BNE .bc_r
  LDX HITR
  LDY T3
  JSR NT_XY
  LDA T4
  BNE .bc_up
  LDA #T_DECK
  STA VDATA
  DEC HITR                     ; the row above as it was
  JSR TILE_AT
  PHA
  LDX HITR
  LDY T3
  JSR NT_XY
  PLA
  STA VDATA
  RTS
.bc_up:
  STA VDATA
  LDX HITR
  DEX
  LDY T3
  JSR NT_XY
  LDA T4
  INC A                        ; the high tile follows the low one
  STA VDATA
.bc_r:
  RTS


; ===============================================================
;  ENEMIES AND HAZARDS: coming in, moving
; ===============================================================
; the next enemy of the deck through a hatch at the top
SPAWNS:
  LDA GSTATE
  BNE .sp_r
  LDA BONUS
  BNE .sp_r
  LDX DKN
  LDA QIDX
  CMP DK_N,X
  BCS .sp_r
  DEC SPAWNT
  BNE .sp_r
  LDA DK_LO,X
  STA PTR
  LDA DK_HI,X
  STA PTR+1
  LDY QIDX
  LDA (PTR),Y
  PHA
  LDX SIDE
  LDA HATCH_X,X
  STA T2
  LDA #32
  STA T3
  PLA
  JSR NEW_OBJ
  BCS .sp_late                 ; no room: a frame later
  LDA SIDE                     ; out of the hatch, towards the middle
  STA O_D,X
  LDA SPDBASE
  STA O_LV,X
  LDA O_K,X
  CMP #K_RIV
  BNE .sp_n
  LDA #1                       ; a riveter comes with its armour
  STA O_H,X
.sp_n:
  INC QIDX
  LDA SIDE
  EOR #1
  STA SIDE
  LDA #150
  SEC
  SBC SPDBASE
  SBC SPDBASE
  SBC SPDBASE
  SBC SPDBASE
  STA SPAWNT
.sp_r:
  RTS
.sp_late:
  INC SPAWNT
  RTS

; a welding spark from a side, at a random height
NEW_SPARK:
  LDA NLEFT
  BEQ .ns_r
  JSR NEXT_RND
  AND #1
  TAY
  LDA SPARK_X,Y
  STA T2
  STY T5
  JSR NEXT_RND
  AND #3
  TAY
  LDA SPARK_Y,Y
  STA T3
  LDA #K_SPARK
  JSR NEW_OBJ
  BCS .ns_r
  LDY T5
  LDA SPARK_VX,Y
  STA O_VXL,X
  LDA SPARK_VXH,Y
  STA O_VXH,X
  LDA #$C0                     ; down at first
  STA O_VYL,X
  STZ O_VYH,X
  LDA #240
  STA O_T,X
  LDA #W_SPARK
  LDX #1
  JMP SFX_WHISTLE
.ns_r:
  RTS

; a bolt hangs from the crane over a random column, then falls
NEW_BOLT:
  JSR NEXT_RND
  AND #$F0
  CMP #$E0
  BCC .nb_x
  LDA #$D0
.nb_x:
  ADC #8
  STA T2
  LDA #16
  STA T3
  LDA #K_BOLT
  JSR NEW_OBJ
  BCS .nb_r
  LDA #60
  STA O_T,X
.nb_r:
  RTS

; an oil slick through a hatch (only one at a time)
NEW_OIL:
  LDX #NOB-1
.no_c:
  LDA O_K,X
  CMP #K_OIL
  BEQ .no_r
  DEX
  BPL .no_c
  LDX SIDE
  LDA HATCH_X,X
  STA T2
  LDA #32
  STA T3
  LDA #K_OIL
  JSR NEW_OBJ
  BCS .no_r
  LDA SIDE
  STA O_D,X
  STZ O_LV,X
.no_r:
  RTS

; A = kind, T2 = x, T3 = y: a new object in X (C = 1: no free slot)
NEW_OBJ:
  PHA
  LDX #NOB-1
.nw_f:
  LDA O_K,X
  BEQ .nw_ok
  DEX
  BPL .nw_f
  PLA
  SEC
  RTS
.nw_ok:
  PLA
  STA O_K,X
  LDA T2
  STA O_X,X
  LDA T3
  STA O_Y,X
  STZ O_XF,X
  STZ O_YF,X
  STZ O_VXL,X
  STZ O_VXH,X
  STZ O_VYL,X
  STZ O_VYH,X
  STZ O_S,X
  STZ O_T,X
  STZ O_LV,X
  STZ O_H,X
  STZ O_D,X
  CLC
  RTS

; X = object: a puff of smoke in its place
TO_PUFF:
  LDA #K_PUFF
  STA O_K,X
  LDA #12
  STA O_T,X
  RTS

; X = spark put out by a bump: 500 to the player CI
SPARK_OUT:
  LDA #$00
  LDY #$05
  JSR PTS_CI_X
  JSR TO_PUFF
  PHX
  LDA #W_SPARK
  JSR SFX_P
  PLX
  RTS


; ===============================================================
;  OBJECTS: one routine per kind, X = slot (kept)
; ===============================================================
OBJECTS:
  LDX #NOB-1
.ob_l:
  STX OI
  LDA O_K,X
  BEQ .ob_n
  CMP #K_SPARK
  BCC .ob_walk
  BEQ .ob_spark
  CMP #K_BOLT
  BEQ .ob_bolt
  CMP #K_PUFF
  BNE .ob_n
  DEC O_T,X                    ; the puff goes away
  BNE .ob_n
  STZ O_K,X
  BRA .ob_n
.ob_walk:
  JSR ENEMY
  BRA .ob_n
.ob_spark:
  JSR SPARK
  BRA .ob_n
.ob_bolt:
  JSR BOLT
.ob_n:
  LDX OI
  DEX
  BPL .ob_l
  RTS

; ---------------------------------------------------------------
; rats, riveters, gulls, oil slicks
; ---------------------------------------------------------------
ENEMY:
  LDA O_S,X
  BEQ EN_WALK
  CMP #2
  BEQ EN_FLIP
  BCS .en_k
  JMP EN_AIR
.en_k:
  JMP EN_KICKED

; turned over: it gets up again after a while, faster
EN_FLIP:
  DEC O_T,X
  BNE .ef_r
  LDA O_LV,X
  CMP #5
  BCS .ef_h
  INC O_LV,X
.ef_h:
  LDA #1
  STA O_S,X
  LDA #$FE
  STA O_VYH,X
  STZ O_VYL,X
  PHX
  LDA #W_UP
  LDX #1
  JSR SFX_WHISTLE
  PLX
.ef_r:
  RTS

; on a deck: walks (a gull waits and hops)
EN_WALK:
  LDA O_K,X
  CMP #K_GULL
  BNE .ew_m
  INC O_T,X                    ; a gull: a hop every 24 frames
  LDA O_T,X
  CMP #24
  BCC .ew_r
  STZ O_T,X
  LDA #1
  STA O_S,X
  LDA #$80
  STA O_VYL,X
  LDA #$FD                     ; -2.5
  STA O_VYH,X
  JSR WALK_X
  JMP WALK_X
.ew_m:
  JSR WALK_X
  LDA O_Y,X                    ; on the floor at a drain: back through a hatch
  CMP #FLOOR_Y
  BNE .ew_s
  LDA O_X,X
  LDY O_D,X
  BEQ .ew_dr
  CMP #3
  BCS .ew_s
  BRA .ew_out
.ew_dr:
  CMP #237
  BCC .ew_s
.ew_out:
  LDA O_X,X                    ; the hatch of the same side, going inwards
  ASL A
  LDA #0
  ROL A
  TAY
  LDA HATCH_X,Y
  STA O_X,X
  TYA
  STA O_D,X
  LDA #32
  STA O_Y,X
  RTS
.ew_s:
  LDA O_X,X                    ; nothing under the feet: it falls
  LDY O_Y,X
  JSR SUPPORT
  BCS .ew_r
  LDA #1
  STA O_S,X
  STZ O_VYL,X
  STZ O_VYH,X
.ew_r:
  RTS

; in the air: forwards and down; it lands on a deck
EN_AIR:
  JSR WALK_X
  CLC
  LDA O_VYL,X
  ADC #GRAV
  STA O_VYL,X
  LDA O_VYH,X
  ADC #0
  CMP #4
  BMI .ea_v
  LDA #4
  STZ O_VYL,X
.ea_v:
  STA O_VYH,X
  CLC
  LDA O_YF,X
  ADC O_VYL,X
  STA O_YF,X
  LDA O_Y,X
  ADC O_VYH,X
  STA O_Y,X
  LDA O_VYH,X
  BMI .ea_r
  LDA O_X,X
  LDY O_Y,X
  JSR LANDING
  BCC .ea_r
  STA O_Y,X
  STZ O_YF,X
  STZ O_VYL,X
  STZ O_VYH,X
  STZ O_S,X
  STZ O_T,X
.ea_r:
  RTS

; kicked: flies away and falls into the sea
EN_KICKED:
  CLC
  LDA O_XF,X
  ADC O_VXL,X
  STA O_XF,X
  LDA O_X,X
  ADC O_VXH,X
  STA O_X,X
  CLC
  LDA O_VYL,X
  ADC #GRAV
  STA O_VYL,X
  LDA O_VYH,X
  ADC #0
  STA O_VYH,X
  CLC
  LDA O_YF,X
  ADC O_VYL,X
  STA O_YF,X
  LDA O_Y,X
  ADC O_VYH,X
  STA O_Y,X
  CMP #200
  BCC .ek_r
  CMP #240
  BCS .ek_r
  STZ O_K,X
  PHX
  LDA #S_SPLASH
  LDY O_X,X
  JSR BOOM_AT
  PLX
.ek_r:
  RTS

; X = enemy: a step along its direction at the speed of its level
; (the last enemy of the deck runs at the top speed)
WALK_X:
  LDY O_LV,X
  LDA O_K,X
  CMP #K_OIL
  BEQ .wx_v
  LDA NLEFT
  CMP #1
  BNE .wx_v
  LDY #5
.wx_v:
  LDA SPD_L,Y
  STA T0
  LDA O_D,X
  BNE .wx_l
  CLC
  LDA O_XF,X
  ADC T0
  STA O_XF,X
  LDA O_X,X
  ADC SPD_H,Y
  STA O_X,X
  RTS
.wx_l:
  SEC
  LDA O_XF,X
  SBC T0
  STA O_XF,X
  LDA O_X,X
  SBC SPD_H,Y
  STA O_X,X
  RTS

; ---------------------------------------------------------------
; a spark: bounces between the top and the floor, crosses the sides
; ---------------------------------------------------------------
SPARK:
  DEC O_T,X
  BNE .sk_m
  JMP TO_PUFF
.sk_m:
  CLC
  LDA O_XF,X
  ADC O_VXL,X
  STA O_XF,X
  LDA O_X,X
  ADC O_VXH,X
  STA O_X,X
  CLC
  LDA O_YF,X
  ADC O_VYL,X
  STA O_YF,X
  LDA O_Y,X
  ADC O_VYH,X
  STA O_Y,X
  CMP #20
  BCC .sk_b
  CMP #156
  BCC .sk_r
.sk_b:
  LDA #0                       ; bounce
  SEC
  SBC O_VYL,X
  STA O_VYL,X
  LDA #0
  SBC O_VYH,X
  STA O_VYH,X
.sk_r:
  RTS

; a bolt: shakes on the crane, then falls through everything
BOLT:
  LDA O_S,X
  BNE .bo_f
  DEC O_T,X
  BNE .bo_r
  INC O_S,X
  RTS
.bo_f:
  LDA O_Y,X
  CLC
  ADC #3
  STA O_Y,X
  CMP #192
  BCC .bo_r
  STZ O_K,X
.bo_r:
  RTS


; ===============================================================
;  TOUCHES: the players against the objects
; ===============================================================
TOUCHES:
  LDX #1
.to_p:
  STX CI
  LDA P_ST,X
  BEQ .to_np
  CMP #3
  BCS .to_np
  LDA P_X,X
  STA T2
  LDA P_Y,X
  STA T3
  LDY #NOB-1
.to_o:
  LDA O_K,Y
  BEQ .to_on
  CMP #K_PUFF
  BEQ .to_on
  LDA O_X,Y                    ; 12 pixels apart at most
  SEC
  SBC T2
  CLC
  ADC #11
  CMP #22
  BCS .to_on
  LDA O_Y,Y
  SEC
  SBC T3
  CLC
  ADC #11
  CMP #22
  BCS .to_on
  STY OI
  JSR TOUCH
  LDX CI
  LDA P_ST,X                   ; hit: no more touches for him
  CMP #3
  BCS .to_np
  LDY OI
.to_on:
  DEY
  BPL .to_o
.to_np:
  LDX CI
  DEX
  BPL .to_p
  RTS

; player CI touches object OI
TOUCH:
  LDX OI
  LDA O_K,X
  CMP #K_BOTTLE
  BNE .tc_e
  STZ O_K,X                    ; a bottle: 800
  DEC NBOT
  LDA #$00
  LDY #$08
  JSR ADD_PTS_CI
  LDA #W_BOTTLE
  JMP SFX_P
.tc_e:
  CMP #K_SPARK
  BCS TC_HIT
  LDA O_S,X
  CMP #3
  BNE .tc_nk
  RTS                          ; already kicked
.tc_nk:
  CMP #2
  BNE TC_HIT
  ; ---- turned over: a kick into the sea
  LDA #3
  STA O_S,X
  LDA #$FD
  STA O_VYH,X
  STZ O_VYL,X
  LDY CI
  LDA O_X,X
  CMP P_X,Y
  LDA #$02
  BCS .tc_k
  LDA #$FE
.tc_k:
  STA O_VXH,X
  STZ O_VXL,X
  LDA O_K,X
  CMP #K_OIL
  BNE .tc_c
  LDA #$00                     ; an oil slick: 500
  LDY #$05
  JSR ADD_PTS_CI
  BRA .tc_s
.tc_c:
  DEC NLEFT
  INC KICKS
  LDX CI                       ; 800, 1600, 2400, 3200 in a row
  LDY P_COMBO,X
  LDA KICK_M,Y
  TAY
  CPY #$32
  BEQ .tc_m
  INC P_COMBO,X
.tc_m:
  LDA #90
  STA P_CT,X
  LDA #$00
  JSR ADD_PTS_CI
.tc_s:
  LDA #W_KICK
  JMP SFX_P
TC_HIT:                        ; an enemy on its feet, a spark, a bolt (global: the tests)
  LDX CI
  LDA P_INV,X
  BNE .tc_r
  LDY OI
  LDA O_K,Y
  STA DEATH
  LDA #3
  STA P_ST,X
  LDA #$FD
  STA P_VYH,X
  STZ P_VYL,X
  DEC LIVES,X
  STZ NOLOSS,X
  INC LOSTN
  LDA #2
  TSB HUDD
  LDA #W_DIE
  JMP SFX_P
.tc_r:
  RTS


; ===============================================================
;  SPRITES: the players and the objects take turns at the front
; ===============================================================
BUILD_SAT:
  STZ SPRI
  LDA FRAME_CNT
  AND #1
  BEQ .bs_p
  JSR SAT_OBJS
  JSR SAT_PLAYERS
  BRA .bs_e
.bs_p:
  JSR SAT_PLAYERS
  JSR SAT_OBJS
.bs_e:
  LDX SPRI
  LDA #$D0
  STA SAT_BUFFER,X
  INX
  STX SATB
  RTS

; OX, OY, ON, OC: one sprite more (keeps X)
ADD_SPR:
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
  RTS

SAT_PLAYERS:
  LDX #1
.sp_l:
  LDA P_ST,X
  BEQ .sp_n
  CMP #4
  BCS .sp_n
  LDA P_INV,X                  ; blinking
  AND #4
  BNE .sp_n
  LDA P_X,X
  STA OX
  LDA P_Y,X
  STA OY
  LDA PCOL,X
  STA OC
  LDA P_ST,X
  CMP #3
  BNE .sp_a
  LDA #PT_MAND
  BRA .sp_put
.sp_a:
  CMP #2
  BNE .sp_g
  LDA #PT_MANJ                 ; in the air
  BRA .sp_d
.sp_g:
  LDA P_VXH,X                  ; on a deck: running or standing
  ORA P_VXL,X
  BEQ .sp_st
  LDA FRAME_CNT
  AND #8
  LSR A
  CLC
  ADC #PT_MANR1
  BRA .sp_d
.sp_st:
  LDA #PT_MAN
.sp_d:
  LDY P_DIR,X                  ; facing left: the mirrored patterns
  BEQ .sp_put
  CLC
  ADC #PT_MANL-PT_MAN
.sp_put:
  STA ON
  JSR ADD_SPR
.sp_n:
  DEX
  BPL .sp_l
  RTS

; the objects, starting from RR
SAT_OBJS:
  LDX RR
  LDA #NOB
  STA T7
.so_l:
  LDA O_K,X
  BEQ .so_n
  LDA O_X,X
  STA OX
  LDA O_Y,X
  STA OY
  JSR OBJ_LOOK
  JSR ADD_SPR
.so_n:
  INX
  CPX #NOB
  BCC .so_w
  LDX #0
.so_w:
  DEC T7
  BNE .so_l
  INC RR
  LDA RR
  CMP #NOB
  BCC .so_r
  STZ RR
.so_r:
  RTS

; X = object: ON / OC (pattern and colour)
OBJ_LOOK:
  LDY O_LV,X                   ; enemies: the colour of their level
  LDA LVCOL,Y
  STA OC
  LDA O_K,X
  CMP #K_RAT
  BNE .ol_v
  LDA O_S,X
  CMP #2
  BCC .ol_rw
  LDA #PT_RATF
  BRA .ol_put
.ol_rw:
  LDA FRAME_CNT
  AND #8
  LSR A
  CLC
  ADC #PT_RAT1
  LDY O_D,X
  BEQ .ol_put
  CLC
  ADC #PT_RATL1-PT_RAT1
  BRA .ol_put
.ol_v:
  CMP #K_RIV
  BNE .ol_g
  LDA O_S,X
  CMP #2
  BCC .ol_vw
  LDA #PT_RIVF
  BRA .ol_put
.ol_vw:
  LDA O_H,X
  BNE .ol_va
  LDA #PT_RIVA                 ; armour gone
  BRA .ol_put
.ol_va:
  LDA #15
  STA OC
  LDA FRAME_CNT
  AND #8
  LSR A
  CLC
  ADC #PT_RIV1
  BRA .ol_put
.ol_g:
  CMP #K_GULL
  BNE .ol_o
  LDA O_S,X
  CMP #2
  BCC .ol_gw
  LDA #PT_GULLF
  BRA .ol_put
.ol_gw:
  LDA #PT_GULL1                ; standing, or wings up in the air
  LDY O_S,X
  BEQ .ol_gd
  LDA #PT_GULL2
.ol_gd:
  LDY O_D,X
  BEQ .ol_put
  CLC
  ADC #PT_GULLL1-PT_GULL1
.ol_put:
  STA ON
  RTS
.ol_o:
  CMP #K_OIL
  BNE .ol_s
  LDA #1                       ; black oil
  STA OC
  LDA FRAME_CNT
  AND #16
  LSR A
  LSR A
  CLC
  ADC #PT_OIL1
  BRA .ol_put
.ol_s:
  CMP #K_SPARK
  BNE .ol_b
  LDA FRAME_CNT
  AND #2
  ASL A
  TAY
  ADC #PT_SPARK1
  STA ON
  LDA #11
  CPY #0
  BEQ .ol_sc
  LDA #9
.ol_sc:
  STA OC
  RTS
.ol_b:
  CMP #K_BOLT
  BNE .ol_t
  LDA #14
  STA OC
  LDA O_S,X                    ; it shakes before falling
  BNE .ol_bp
  LDA FRAME_CNT
  AND #4
  LSR A
  LSR A
  CLC
  ADC OX
  STA OX
.ol_bp:
  LDA #PT_BOLT
  BRA .ol_put
.ol_t:
  CMP #K_BOTTLE
  BNE .ol_p
  LDA #12
  STA OC
  LDA #PT_BOTTLE
  BRA .ol_put
.ol_p:
  LDA #15
  STA OC
  LDA #PT_PUFF
  BRA .ol_put


; ===============================================================
;  SCREEN: VRAM, texts, sprites, sound (from dune ranger)
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

; the colours of the game tiles in the three thirds, the colour 4 changed into
; the hull colour of the ship (HULLC)
LOAD_COLS:
  STZ T7
.lc_t:
  LDX #0
.lc_e:
  LDA TCOL_LIST,X
  CMP #$FF
  BEQ .lc_nt
  STA T0
  ASL A
  ASL A
  ASL A
  STA VREG
  LDA T0
  LSR A
  LSR A
  LSR A
  LSR A
  LSR A
  STA T1
  LDA T7
  ASL A
  ASL A
  ASL A
  CLC
  ADC T1
  ADC #($20 | VDP_WRITE_VRAM_BIT)
  STA VREG
  LDA TCOL_LIST+1,X
  ASL A
  ASL A
  ASL A
  STA T3
  LDA TCOL_LIST+2,X
  STA PTR
  LDA TCOL_LIST+3,X
  STA PTR+1
  LDY #0
.lc_b:
  LDA (PTR),Y
  JSR HULLSUB
  STA VDATA
  INY
  CPY T3
  BNE .lc_b
  TXA
  CLC
  ADC #4
  TAX
  BRA .lc_e
.lc_nt:
  INC T7
  LDA T7
  CMP #3
  BNE .lc_t
  RTS

; A = colour byte: the nibbles equal to 4 become HULLC
HULLSUB:
  STA T4
  AND #$0F
  CMP #4
  BNE .hs_l
  LDA HULLC
.hs_l:
  STA T5
  LDA T4
  AND #$F0
  CMP #$40
  BNE .hs_h
  LDA HULLC
  ASL A
  ASL A
  ASL A
  ASL A
.hs_h:
  ORA T5
  RTS

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
SC_COL:     .byte 0,26                         ; score of Carlo / Fabio: column on row 1
LV_COL:     .byte 7,20                         ; their lives on row 1
PCOL:       .byte 7,11                         ; Carlo cyan, Fabio yellow
START_X:    .byte 64,176                       ; where they start a deck (on the floor)
RESP_X:     .byte 40,200                       ; where they come back (over the top deck)
HATCH_X:    .byte 0,240                        ; the hatches: left, right
SPARK_X:    .byte 0,240
SPARK_Y:    .byte 40,72,104,136
SPARK_VX:   .byte $40,$C0                      ; +1.25 / -1.25
SPARK_VXH:  .byte $01,$FE
; speed of the levels 0-5: 0.5, 0.75, 1, 1.25, 1.5, 1.75 pixels a frame
SPD_L:      .byte $80,$C0,$00,$40,$80,$C0
SPD_H:      .byte $00,$00,$01,$01,$01,$01
LVCOL:      .byte 14,15,3,9,10,1               ; colour of the enemies by level
KICK_M:     .byte $08,$16,$24,$32              ; kicks in a row: 800 1600 2400 3200 (BCD hundreds)
S_BIG = S_SPLASH                               ; (lib_sound: a big noise is not cut by a small one)

; title: Carlo, Fabio, the rat, the riveter, the gull (sprite Y, X, pattern, colour)
TITLE_NS = 5
TITLE_SY:   .byte 91,91,91,107,123
TITLE_SX:   .byte 184,208,40,40,40
TITLE_SN:   .byte PT_MANR1,PT_MANLR1,PT_RAT1,PT_RIV1,PT_GULL1
TITLE_SC:   .byte 7,11,14,15,15

; text records: row, column, characters, 0   (end of list: $FF)
TXT_TOP:
  .byte 0,0,"CARLO",0
  .byte 0,14,"HI",0
  .byte $FF
TXT_TOP2:
  .byte 0,27,"FABIO",0,$FF
TXT_BUTTONS:
  .byte 20,6,"BUTTON 1 = 1 PLAYER",0
  .byte 21,6,"BUTTON 2 = 2 PLAYERS",0
  .byte 23,3,"DEVELOPED BY BOOGS & CCAI",0
  .byte $FF
TXT_TITLE:
  .byte 9,4,"BUMP THE DECKS FROM BELOW",0
  .byte 10,4,"THEN KICK THEM INTO THE SEA",0
  .byte 12,8,"RAT",0
  .byte 14,8,"RIVETER  BUMP TWICE",0
  .byte 16,8,"GULL  BUMP IT STANDING",0
  .byte 18,4,"KICK 800 1600 2400 3200",0
  .byte $FF
TXT_SHIP:   .byte "SHIP "
TXT_DECKH:  .byte "DECK "
TXT_BTIME:  .byte "BONUS TIME "
TXT_DECK:
  .byte 8,12,"DECK ",0,$FF
TXT_BONUSR:
  .byte 8,10,"BONUS ROUND",0
  .byte 13,4,"CATCH THE LAUNCH BOTTLES",0
  .byte $FF
TXT_CLEAR:
  .byte 8,11,"DECK CLEAR",0,$FF
TXT_ALLB:
  .byte 8,7,"ALL BOTTLES  5000",0,$FF
TXT_LAUNCH:
  .byte 8,6,"THE SHIP IS LAUNCHED",0,$FF
TXT_OVER:
  .byte 11,11,"GAME OVER",0,$FF

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
;  GRAPHICS, SCREEN, DECKS AND SOUND TABLES (generated)
; ===============================================================
; SUPER CARLO: generated by dev/gen_super_carlo.js (do not edit by hand)

; sprite patterns (16x16), value = pattern number * 4
PT_MAN = 0
PT_MANR1 = 4
PT_MANR2 = 8
PT_MANJ = 12
PT_MANL = 16
PT_MANLR1 = 20
PT_MANLR2 = 24
PT_MANLJ = 28
PT_MAND = 32
PT_RAT1 = 36
PT_RAT2 = 40
PT_RATL1 = 44
PT_RATL2 = 48
PT_RATF = 52
PT_RIV1 = 56
PT_RIV2 = 60
PT_RIVA = 64
PT_RIVF = 68
PT_GULL1 = 72
PT_GULL2 = 76
PT_GULLL1 = 80
PT_GULLL2 = 84
PT_GULLF = 88
PT_OIL1 = 92
PT_OIL2 = 96
PT_SPARK1 = 100
PT_SPARK2 = 104
PT_BOLT = 108
PT_BOTTLE = 112
PT_PUFF = 116
SPR_LEN = 960
SPR_PAGES = 4
SPRITES:
  .byte $07,$0F,$1F,$0D,$0F,$07,$0F,$1F,$1B,$1B,$0F,$0E,$0C,$0C,$1C,$00,$C0,$E0,$F0,$60,$E0,$C0,$E0,$F0,$B0,$B0,$E0,$E0,$60,$60,$70,$00
  .byte $07,$0F,$1F,$0D,$0F,$07,$0F,$1F,$33,$01,$03,$07,$0E,$1C,$18,$00,$C0,$E0,$F0,$60,$E0,$C0,$E0,$F4,$CC,$E0,$F0,$38,$18,$18,$1C,$00
  .byte $07,$0F,$1F,$0D,$0F,$07,$0F,$3F,$63,$03,$03,$03,$03,$03,$03,$00,$C0,$E0,$F0,$60,$E0,$C0,$E0,$F0,$C0,$E0,$E0,$60,$60,$70,$80,$00
  .byte $07,$0F,$1F,$0D,$0F,$07,$0F,$1F,$33,$03,$07,$0E,$1C,$38,$00,$00,$C6,$E0,$F0,$60,$E0,$C0,$EC,$F8,$C0,$E0,$70,$30,$30,$38,$00,$00
  .byte $03,$07,$0F,$06,$07,$03,$07,$0F,$0D,$0D,$07,$07,$06,$06,$0E,$00,$E0,$F0,$F8,$B0,$F0,$E0,$F0,$F8,$D8,$D8,$F0,$70,$30,$30,$38,$00
  .byte $03,$07,$0F,$06,$07,$03,$07,$2F,$33,$07,$0F,$1C,$18,$18,$38,$00,$E0,$F0,$F8,$B0,$F0,$E0,$F0,$F8,$CC,$80,$C0,$E0,$70,$38,$18,$00
  .byte $03,$07,$0F,$06,$07,$03,$07,$0F,$03,$07,$07,$06,$06,$0E,$01,$00,$E0,$F0,$F8,$B0,$F0,$E0,$F0,$FC,$C6,$C0,$C0,$C0,$C0,$C0,$C0,$00
  .byte $63,$07,$0F,$06,$07,$03,$37,$1F,$03,$07,$0E,$0C,$0C,$1C,$00,$00,$E0,$F0,$F8,$B0,$F0,$E0,$F0,$F8,$CC,$C0,$E0,$70,$38,$1C,$00,$00
  .byte $00,$10,$08,$07,$0F,$1F,$0B,$0F,$07,$0F,$1F,$37,$37,$0C,$18,$30,$00,$10,$20,$C0,$E0,$F0,$A0,$E0,$C0,$E0,$F0,$D8,$D8,$60,$30,$18
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$0F,$3F,$7F,$BF,$98,$50,$00,$00,$00,$00,$00,$00,$00,$00,$30,$78,$FA,$FC,$FC,$F8,$30,$10,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$0F,$3F,$7F,$BF,$8C,$44,$00,$00,$00,$00,$00,$00,$00,$00,$30,$78,$FA,$FC,$FC,$F8,$60,$40,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$0C,$1E,$5F,$3F,$3F,$1F,$0C,$08,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$F0,$FC,$FE,$FD,$19,$0A,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$0C,$1E,$5F,$3F,$3F,$1F,$06,$02,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$F0,$FC,$FE,$FD,$31,$22,$00,$00
  .byte $00,$00,$50,$98,$BF,$7F,$3F,$0F,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$10,$30,$F8,$FC,$FC,$FA,$78,$30,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$07,$0F,$1B,$1F,$0F,$67,$7F,$7F,$1F,$1F,$0C,$1C,$3C,$00,$00,$00,$E0,$F0,$D8,$F8,$F0,$E6,$FE,$FE,$F8,$F8,$30,$38,$3C,$00
  .byte $00,$00,$07,$0F,$1B,$1F,$0F,$67,$7F,$7F,$1F,$1F,$06,$0E,$1E,$00,$00,$00,$E0,$F0,$D8,$F8,$F0,$E6,$FE,$FE,$F8,$F8,$60,$70,$78,$00
  .byte $00,$00,$09,$07,$1B,$1F,$0B,$27,$53,$40,$17,$1F,$0C,$1C,$3C,$00,$00,$00,$90,$E0,$D8,$F8,$D0,$E4,$CA,$02,$E8,$F8,$30,$38,$3C,$00
  .byte $00,$3C,$1C,$0C,$1F,$1F,$7F,$7F,$67,$0F,$1F,$1B,$0F,$07,$00,$00,$00,$3C,$38,$30,$F8,$F8,$FE,$FE,$E6,$F0,$F8,$D8,$F0,$E0,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$20,$3F,$1F,$0F,$02,$02,$06,$00,$00,$00,$00,$00,$00,$1C,$3E,$1F,$3C,$F8,$F8,$F0,$40,$40,$C0,$00,$00
  .byte $00,$60,$38,$1E,$0F,$07,$03,$01,$3F,$1F,$0F,$00,$00,$00,$00,$00,$00,$00,$00,$1C,$3E,$DF,$F8,$FC,$F8,$F0,$C0,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$38,$7C,$F8,$3C,$1F,$1F,$0F,$02,$02,$03,$00,$00,$00,$00,$00,$00,$00,$00,$00,$04,$FC,$F8,$F0,$40,$40,$60,$00,$00
  .byte $00,$00,$00,$38,$7C,$FB,$1F,$3F,$1F,$0F,$03,$00,$00,$00,$00,$00,$00,$06,$1C,$78,$F0,$E0,$C0,$80,$FC,$F8,$F0,$00,$00,$00,$00,$00
  .byte $00,$00,$06,$02,$02,$0F,$1F,$3F,$20,$00,$00,$00,$00,$00,$00,$00,$00,$00,$C0,$40,$40,$F0,$F8,$F8,$3C,$1F,$3E,$1C,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$0F,$3F,$7F,$3F,$0F,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$C0,$F0,$FC,$FC,$F0,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$03,$0F,$3F,$1F,$07,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$F0,$FC,$FE,$FC,$F0,$00
  .byte $00,$00,$00,$01,$11,$09,$07,$3F,$07,$09,$11,$01,$00,$00,$00,$00,$00,$00,$00,$00,$10,$20,$C0,$F8,$C0,$20,$10,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$10,$09,$05,$03,$1F,$03,$05,$09,$10,$00,$00,$00,$00,$00,$00,$00,$10,$20,$40,$80,$F0,$80,$40,$20,$10,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$07,$0F,$0F,$07,$01,$01,$01,$01,$01,$01,$00,$00,$00,$00,$00,$00,$E0,$F0,$F0,$E0,$80,$80,$80,$80,$80,$80,$00,$00
  .byte $00,$01,$01,$03,$03,$07,$07,$06,$07,$06,$07,$07,$07,$03,$00,$00,$00,$80,$80,$C0,$C0,$E0,$E0,$60,$E0,$60,$E0,$E0,$E0,$C0,$00,$00
  .byte $00,$00,$10,$08,$45,$20,$07,$CF,$07,$20,$45,$08,$10,$00,$00,$00,$00,$00,$40,$84,$10,$08,$C0,$E6,$C0,$08,$10,$84,$40,$00,$00,$00

; game tiles: patterns and colours (colour 4 = the hull)
TILEP0:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$07,$1F,$38,$3F,$7F,$7F,$7F,$00,$E0,$F8,$1C,$FC,$FE,$FE,$FE,$7F,$7F,$7F,$3F,$38,$1F,$07,$00
  .byte $FE,$FE,$FE,$FC,$1C,$F8,$E0,$00
TILEC0:
  .byte $14,$14,$14,$14,$14,$14,$14,$14,$E4,$E4,$E4,$E4,$B4,$B4,$B4,$B4,$E4,$E4,$E4,$E4,$B4,$B4,$B4,$B4,$B4,$B4,$B4,$B4,$E4,$E4,$E4,$E4
  .byte $B4,$B4,$B4,$B4,$E4,$E4,$E4,$E4
TILEP1:
  .byte $FF,$FF,$BF,$FF,$FF,$FD,$FF,$00,$BF,$FF,$FF,$FD,$FF,$00,$00,$00,$00,$00,$00,$00,$00,$00,$FF,$FF,$FF,$FD,$FF,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$FF,$FF,$BF,$FF
TILEC1:
  .byte $F1,$E1,$E1,$E1,$E1,$E1,$11,$14,$E1,$E1,$E1,$E1,$11,$14,$14,$14,$14,$14,$14,$14,$14,$14,$F1,$E1,$E1,$E1,$11,$14,$14,$14,$14,$14
  .byte $14,$14,$14,$14,$F1,$E1,$E1,$E1
TILEP2:
  .byte $FF,$80,$BF,$A0,$A0,$A0,$A0,$A0,$FF,$01,$FD,$05,$05,$05,$05,$05,$A0,$A0,$A0,$A0,$A0,$BF,$80,$FF,$05,$05,$05,$05,$05,$FD,$01,$FF
  .byte $FF,$AA,$55,$FF,$00,$00,$00,$00,$FF,$AA,$55,$FF,$00,$00,$00,$00,$00,$0F,$3F,$70,$60,$C0,$C0,$C0,$00,$F0,$FC,$0E,$06,$03,$03,$03
  .byte $C0,$C0,$C0,$C0,$C0,$C0,$C0,$C0,$03,$03,$03,$03,$03,$03,$03,$03,$FF,$AA,$00,$10,$00,$02,$00,$FF,$FF,$3C,$7E,$3C,$3C,$3C,$7E,$FF
  .byte $0F,$1F,$39,$79,$FF,$FF,$7F,$3F,$F0,$F8,$9C,$9E,$FF,$FF,$FE,$FC,$FF,$80,$98,$98,$80,$FF,$30,$30,$FF,$01,$01,$01,$01,$FF,$0C,$0C
  .byte $FF,$80,$99,$99,$80,$FF,$30,$30,$FF,$01,$81,$81,$01,$FF,$0C,$0C,$FF,$80,$99,$99,$80,$FF,$30,$30,$FF,$01,$99,$99,$01,$FF,$0C,$0C
  .byte $00,$3C,$7E,$FF,$FF,$01,$00,$00
TILEC2:
  .byte $B4,$B4,$B4,$E1,$E1,$E1,$E1,$E1,$B4,$B4,$B4,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$B4,$B4,$B4,$E1,$E1,$E1,$E1,$E1,$B4,$B4,$B4
  .byte $B4,$B4,$B4,$B4,$B4,$B4,$B4,$B4,$B4,$B4,$B4,$B4,$B4,$B4,$B4,$B4,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
  .byte $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$1E,$E1,$E1,$1E,$EE,$1E,$EE,$1E,$1E,$6E,$6E,$6E,$6E,$6E,$6E,$1E
  .byte $94,$94,$94,$94,$84,$84,$64,$64,$94,$94,$94,$94,$84,$84,$64,$64,$E1,$E1,$B1,$B1,$E1,$E1,$E4,$E4,$E1,$E1,$B1,$B1,$E1,$E1,$E4,$E4
  .byte $E1,$E1,$B1,$B1,$E1,$E1,$E4,$E4,$E1,$E1,$B1,$B1,$E1,$E1,$E4,$E4,$E1,$E1,$B1,$B1,$E1,$E1,$E4,$E4,$E1,$E1,$B1,$B1,$E1,$E1,$E4,$E4
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1

; the screen: rows 2-22 of the name table
SCREEN:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $68,$69,$00,$00,$00,$00,$00,$01,$02,$00,$00,$00,$01,$02,$00,$00,$00,$00,$01,$02,$00,$00,$00,$01,$02,$00,$00,$00,$00,$00,$68,$69
  .byte $6A,$6B,$00,$00,$00,$00,$00,$03,$04,$00,$00,$00,$03,$04,$00,$00,$00,$00,$03,$04,$00,$00,$00,$03,$04,$00,$00,$00,$00,$00,$6A,$6B
  .byte $6C,$6D,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$6C,$6D
  .byte $60,$60,$60,$60,$60,$60,$60,$60,$60,$60,$60,$60,$00,$00,$00,$00,$00,$00,$00,$00,$60,$60,$60,$60,$60,$60,$60,$60,$60,$60,$60,$60
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$01,$02,$00,$00,$00,$00,$00,$00,$01,$02,$00,$00,$01,$02,$00,$00,$00,$00,$00,$00,$01,$02,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$03,$04,$00,$00,$00,$00,$00,$00,$03,$04,$00,$00,$03,$04,$00,$00,$00,$00,$00,$00,$03,$04,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $60,$60,$60,$60,$00,$00,$00,$00,$60,$60,$60,$60,$60,$60,$60,$60,$60,$60,$60,$60,$60,$60,$60,$60,$00,$00,$00,$00,$60,$60,$60,$60
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$01,$02,$00,$00,$00,$00,$00,$01,$02,$00,$00,$00,$00,$00,$00,$01,$02,$00,$00,$00,$00,$00,$01,$02,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$03,$04,$00,$00,$00,$00,$00,$03,$04,$00,$00,$00,$00,$00,$00,$03,$04,$00,$00,$00,$00,$00,$03,$04,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $60,$60,$60,$60,$60,$60,$60,$60,$60,$60,$60,$60,$00,$00,$00,$74,$75,$00,$00,$00,$60,$60,$60,$60,$60,$60,$60,$60,$60,$60,$60,$60
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$7A,$7B,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$01,$02,$00,$00,$00,$01,$02,$00,$00,$00,$00,$00,$00,$00,$00,$01,$02,$00,$00,$00,$01,$02,$00,$00,$00,$00,$00
  .byte $6E,$6F,$00,$00,$00,$03,$04,$00,$00,$00,$03,$04,$00,$00,$00,$00,$00,$00,$00,$00,$03,$04,$00,$00,$00,$03,$04,$00,$00,$00,$6E,$6F
  .byte $70,$71,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$70,$71
  .byte $60,$60,$60,$60,$60,$60,$60,$60,$60,$60,$60,$60,$60,$60,$60,$60,$60,$60,$60,$60,$60,$60,$60,$60,$60,$60,$60,$60,$60,$60,$60,$60
  .byte $72,$72,$72,$73,$72,$72,$72,$72,$72,$72,$72,$73,$72,$72,$72,$72,$72,$72,$72,$73,$72,$72,$72,$72,$72,$72,$72,$73,$72,$72,$72,$72

; big letters of the title
BIG_TOP:
  .byte $00,$07,$07,$18,$18,$18,$18,$07,$00,$E0,$E0,$18,$18,$00,$00,$E0,$00,$18,$18,$18,$18,$18,$18,$18,$00,$18,$18,$18,$18,$18,$18,$18
  .byte $00,$1F,$1F,$18,$18,$18,$18,$1F,$00,$E0,$E0,$18,$18,$18,$18,$E0,$00,$1F,$1F,$18,$18,$18,$18,$1F,$00,$F8,$F8,$00,$00,$00,$00,$E0
  .byte $00,$1F,$1F,$18,$18,$18,$18,$1F,$00,$E0,$E0,$18,$18,$18,$18,$E0,$00,$07,$07,$18,$18,$18,$18,$18,$00,$E0,$E0,$18,$18,$00,$00,$00
  .byte $00,$01,$01,$06,$06,$18,$18,$18,$00,$80,$80,$60,$60,$18,$18,$18,$00,$18,$18,$18,$18,$18,$18,$18,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$07,$07,$18,$18,$18,$18,$18,$00,$E0,$E0,$18,$18,$18,$18,$18
BIG_BOT:
  .byte $07,$00,$00,$18,$18,$07,$07,$00,$E0,$18,$18,$18,$18,$E0,$E0,$00,$18,$18,$18,$18,$18,$07,$07,$00,$18,$18,$18,$18,$18,$E0,$E0,$00
  .byte $1F,$18,$18,$18,$18,$18,$18,$00,$E0,$00,$00,$00,$00,$00,$00,$00,$1F,$18,$18,$18,$18,$1F,$1F,$00,$E0,$00,$00,$00,$00,$F8,$F8,$00
  .byte $1F,$19,$19,$18,$18,$18,$18,$00,$E0,$80,$80,$60,$60,$18,$18,$00,$18,$18,$18,$18,$18,$07,$07,$00,$00,$00,$00,$18,$18,$E0,$E0,$00
  .byte $18,$1F,$1F,$18,$18,$18,$18,$00,$18,$F8,$F8,$18,$18,$18,$18,$00,$18,$18,$18,$18,$18,$1F,$1F,$00,$00,$00,$00,$00,$00,$F8,$F8,$00
  .byte $18,$18,$18,$18,$18,$07,$07,$00,$18,$18,$18,$18,$18,$E0,$E0,$00
TXT_BIG:
  .byte 3,5,160,161,162,163,164,165,166,167,168,169,32,32,170,171,172,173,168,169,174,175,176,177,0
  .byte 4,5,192,193,194,195,196,197,198,199,200,201,32,32,202,203,204,205,200,201,206,207,208,209,0
  .byte $FF

; decks: the enemies of every deck (1 rat, 2 riveter, 3 gull), 0 = end
DK0:
  .byte $01,$01,$01,$00
DK1:
  .byte $01,$01,$02,$01,$00
DK2:
  .byte $02,$01,$02,$01,$01,$00
DK3:
  .byte $03,$01,$03,$01,$00
DK4:
  .byte $02,$03,$02,$03,$01,$00
DK5:
  .byte $01,$02,$03,$01,$02,$03,$00
DK_LO:
  .byte <DK0,<DK1,<DK2,<DK3,<DK4,<DK5
DK_HI:
  .byte >DK0,>DK1,>DK2,>DK3,>DK4,>DK5
DK_N:
  .byte $03,$04,$05,$04,$05,$06
; names of the decks (16 characters)
DECK_TXT:
  .byte "THE HOLD        "
  .byte "THE ENGINE DECK "
  .byte "THE CAR DECK    "
  .byte "THE CABIN DECK  "
  .byte "THE PROMENADE   "
  .byte "THE SUN DECK    "
; hull colour of the ships
HULLS:
  .byte $04,$06,$0C,$0D
; bottles of the bonus round: x, y
BOT_X:
  .byte $10,$40,$B0,$E0,$48,$A8,$18,$60,$98,$E8
BOT_Y:
  .byte $20,$20,$20,$20,$48,$48,$70,$70,$70,$70
NBOTTLES = 10

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
  .byte $25,$06,$2A,$06,$2A,$06,$2C,$06,$2E,$0C,$2A,$0C,$31,$0C,$2E,$06,$2A,$06,$2C,$18,$25,$06,$29,$06,$29,$06,$2A,$06,$2C,$0C,$29,$0C
  .byte $2F,$0C,$2C,$06,$29,$06,$2A,$18,$2E,$06,$2F,$06,$31,$0C,$31,$06,$33,$06,$31,$0C,$2E,$0C,$2A,$0C,$2C,$06,$2E,$06,$2F,$0C,$2C,$0C
  .byte $29,$0C,$2A,$24,$FF
SG0_1:
  .byte $22,$18,$25,$18,$23,$18,$20,$18,$20,$18,$23,$18,$22,$18,$22,$18,$1E,$18,$1E,$18,$23,$18,$20,$0C,$25,$0C,$22,$24,$FF
SG0_2:
  .byte $12,$0C,$0D,$0C,$12,$0C,$0D,$0C,$0D,$0C,$08,$0C,$0D,$0C,$08,$0C,$0D,$0C,$08,$0C,$0D,$0C,$08,$0C,$12,$0C,$0D,$0C,$12,$0C,$0D,$0C
  .byte $12,$0C,$0D,$0C,$12,$0C,$0D,$0C,$0B,$0C,$12,$0C,$0D,$0C,$0D,$0C,$12,$0C,$0D,$0C,$06,$0C,$FF
SG0_3:
  .byte $01,$0C,$03,$0C,$02,$0C,$03,$0C,$01,$0C,$03,$0C,$02,$0C,$03,$0C,$01,$0C,$03,$0C,$02,$0C,$03,$0C,$01,$0C,$03,$0C,$02,$0C,$03,$0C
  .byte $01,$0C,$03,$0C,$02,$0C,$03,$0C,$01,$0C,$03,$0C,$02,$0C,$03,$0C,$01,$0C,$02,$0C,$04,$0C,$FF
SG1_0:
  .byte $2A,$06,$2E,$06,$31,$06,$36,$0C,$35,$06,$31,$06,$33,$06,$2F,$06,$2C,$06,$31,$12,$00,$06,$36,$18,$FF
SG1_1:
  .byte $22,$18,$23,$18,$25,$18,$2E,$18,$FF
SG1_2:
  .byte $12,$0C,$0D,$0C,$0B,$0C,$0D,$0C,$12,$0C,$0D,$0C,$06,$18,$FF
SG1_3:
  .byte $01,$06,$03,$06,$03,$06,$02,$06,$01,$06,$03,$06,$03,$06,$02,$06,$01,$06,$03,$06,$02,$06,$02,$06,$01,$0C,$02,$0C,$04,$18,$FF
SG2_0:
  .byte $31,$06,$2E,$06,$2A,$06,$31,$06,$33,$06,$2F,$06,$2C,$06,$33,$06,$35,$06,$31,$06,$2C,$06,$35,$06,$36,$1E,$FF
SG2_1:
  .byte $22,$18,$23,$18,$25,$18,$22,$1E,$FF
SG2_2:
  .byte $12,$0C,$12,$0C,$0B,$0C,$0B,$0C,$0D,$0C,$0D,$0C,$06,$1E,$FF
SG2_3:
  .byte $02,$06,$03,$06,$03,$06,$03,$06,$02,$06,$03,$06,$03,$06,$03,$06,$02,$06,$03,$06,$03,$06,$03,$06,$04,$1E,$FF
SG3_0:
  .byte $25,$08,$25,$08,$25,$08,$2A,$18,$2C,$08,$2E,$08,$2F,$08,$31,$18,$2E,$08,$2A,$08,$2E,$08,$31,$10,$33,$10,$31,$08,$2F,$08,$2E,$08
  .byte $2C,$08,$2A,$28,$FF
SG3_1:
  .byte $22,$18,$22,$18,$25,$18,$25,$18,$2A,$18,$2A,$10,$23,$10,$29,$20,$22,$28,$FF
SG3_2:
  .byte $06,$18,$12,$18,$06,$18,$0D,$18,$06,$18,$0F,$10,$0B,$10,$0D,$20,$06,$28,$FF
SG3_3:
  .byte $01,$08,$01,$08,$01,$08,$02,$18,$01,$08,$01,$08,$01,$08,$02,$18,$01,$08,$03,$08,$03,$08,$02,$10,$02,$10,$01,$08,$01,$08,$01,$08
  .byte $01,$08,$04,$28,$FF

; one-shot tone effects: period and volume for every frame
WH_TL:
  .byte $00,$7D,$61,$50,$43,$3A,$33,$2E,$2A,$5B,$5B,$D0,$68,$45,$34,$2A,$23,$23,$20,$1D,$1B,$1A,$18,$47,$47,$47,$35,$35,$35,$2A,$2A,$2A
  .byte $2A,$1C,$07,$F6,$EA,$E3,$DF,$E0,$E6,$F0,$FE,$12,$29,$43,$5E,$75,$83,$86,$7C,$68,$4E,$34,$1B,$06,$F5,$EA,$E2,$DF,$E1,$E6,$F1,$FF
  .byte $13,$2A,$45,$5F,$76,$84,$86,$7B,$67,$28,$28,$1E,$1E,$1E,$1E,$50,$50,$50,$50,$50,$50,$54,$54,$54,$54,$54,$54,$5A,$5A,$5A,$5A,$5A
  .byte $5A,$5F,$62,$66,$6A,$6F,$74,$79,$7F,$86,$8D,$96,$9F,$A9,$B5,$C3,$D3,$E5,$FC,$17,$39,$3C,$3C,$3C,$3C,$00,$00,$2F,$2F,$2F,$2F,$00
  .byte $00,$28,$28,$28,$28,$00,$00,$1E,$1E,$1E,$1E,$1E,$1E,$B3,$B3,$B3,$B3,$B3,$B3,$B3,$B3,$BD,$BD,$BD,$BD,$BD,$BD,$BD,$BD,$C9,$C9,$C9
  .byte $C9,$C9,$C9,$C9,$C9,$D5,$D5,$D5,$D5,$D5,$D5,$D5,$D5,$D5,$D5,$D5,$D5,$D5,$D5,$D5,$D5,$34,$38,$3D,$43,$4A,$53,$5E,$6C,$80,$9C,$27
  .byte $1A,$27,$1A,$27,$1A,$27,$1A,$27,$1A,$18,$20,$20,$5A,$5A,$5A,$5A,$47,$47,$47,$47,$3C,$3C,$3C,$2D,$2D,$2D,$2D,$2D,$2D,$2D,$2D
WH_TH:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$01,$01,$00,$00,$00,$00,$00,$00,$00,$00,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $01,$01,$01,$01,$01,$01,$01,$01,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
WH_VOL:
  .byte $00,$0B,$0A,$0A,$09,$08,$07,$07,$06,$07,$04,$0D,$0C,$0C,$0B,$0B,$0A,$0A,$09,$08,$06,$05,$04,$0B,$0A,$09,$0B,$0A,$09,$0B,$09,$07
  .byte $05,$0E,$0E,$0E,$0E,$0E,$0E,$0E,$0E,$0E,$0E,$0E,$0E,$0E,$0E,$0E,$0E,$0E,$0E,$0E,$0E,$0E,$0E,$0E,$0E,$0E,$0E,$0E,$0E,$0E,$0E,$0E
  .byte $0D,$0C,$0B,$0A,$09,$08,$07,$06,$05,$0C,$0A,$0C,$0A,$08,$06,$0D,$0D,$0C,$0C,$0B,$0B,$0D,$0D,$0C,$0C,$0B,$0B,$0D,$0D,$0C,$0C,$0B
  .byte $0B,$0D,$0C,$0C,$0B,$0B,$0A,$0A,$09,$09,$08,$08,$07,$07,$06,$06,$05,$05,$04,$04,$03,$0D,$0C,$0A,$09,$00,$00,$0D,$0C,$0A,$09,$00
  .byte $00,$0D,$0C,$0A,$09,$00,$00,$0D,$0B,$09,$08,$06,$04,$0C,$0B,$0A,$09,$09,$08,$07,$06,$0C,$0B,$0A,$09,$09,$08,$07,$06,$0C,$0B,$0A
  .byte $09,$09,$08,$07,$06,$0C,$0C,$0B,$0B,$0A,$0A,$0A,$09,$09,$08,$08,$08,$07,$07,$06,$06,$0A,$09,$09,$08,$07,$07,$06,$05,$05,$04,$09
  .byte $09,$08,$08,$07,$07,$06,$06,$05,$05,$0A,$08,$05,$0C,$0B,$0A,$09,$0C,$0B,$0A,$09,$0C,$0B,$09,$0D,$0C,$0A,$09,$07,$06,$04,$03
WH_START:
  .byte $00,$01,$09,$0B,$17,$21,$49,$4F,$75,$8D,$B5,$BF,$C9,$CC
WH_LEN:
  .byte $00,$08,$02,$0C,$0A,$28,$06,$26,$18,$28,$0A,$0A,$03,$13
W_JUMP = 1
W_STEP = 2
W_KICK = 3
W_UP = 4
W_SIREN = 5
W_BOTTLE = 6
W_DIE = 7
W_EXTRA = 8
W_OVER = 9
W_OUT = 10
W_SPARK = 11
W_KEY = 12
W_SIGN = 13

; noise effects: noise volume / period, low tone volume / period for every frame
EX_NV:
  .byte $00,$0C,$0A,$08,$06,$04,$02,$00,$00,$0D,$0D,$0C,$0C,$0B,$0B,$0A,$0A,$09,$09,$08,$08,$07,$07,$06,$06,$05,$05,$04,$04,$03,$03,$02
  .byte $02,$01,$01,$00,$00,$00,$00,$0B,$0A,$09,$08,$07,$06,$05,$04,$03,$02,$01,$00
EX_NP:
  .byte $00,$16,$16,$16,$16,$16,$16,$16,$16,$03,$03,$03,$03,$03,$03,$03,$03,$04,$04,$04,$04,$04,$04,$04,$04,$05,$05,$05,$05,$05,$05,$05
  .byte $05,$06,$06,$06,$06,$06,$06,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
EX_VC:
  .byte $00,$0D,$0B,$09,$07,$05,$03,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$0C,$0B,$0A,$09,$08,$07,$06,$05,$04,$03,$02,$01
EX_TL:
  .byte $00,$7D,$7D,$7D,$7D,$7D,$7D,$7D,$7D,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$9C,$91,$9C,$91,$9C,$91,$9C,$91,$9C,$91,$9C,$91
EX_TH:
  .byte $00,$03,$03,$03,$03,$03,$03,$03,$03,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
EX_START:
  .byte $00,$01,$09,$27
EX_LEN:
  .byte $00,$08,$1E,$0C
S_BUMP = 1
S_SPLASH = 2
S_CLANG = 3

GFX_LOAD:
  .byte 1, $00,$41, <512,>512, <FONT,>FONT
  .byte 2, $00,$61, <512,>512, $F1,0
  .byte 1, $00,$45, <144,>144, <BIG_TOP,>BIG_TOP
  .byte 1, $00,$46, <144,>144, <BIG_BOT,>BIG_BOT
  .byte 2, $00,$65, <144,>144, $B1,0
  .byte 2, $00,$66, <144,>144, $91,0
  .byte 1, $00,$40, <40,>40, <TILEP0,>TILEP0
  .byte 1, $00,$43, <40,>40, <TILEP1,>TILEP1
  .byte 1, $40,$43, <168,>168, <TILEP2,>TILEP2
  .byte 1, $00,$49, <512,>512, <FONT,>FONT
  .byte 2, $00,$69, <512,>512, $F1,0
  .byte 1, $00,$4D, <144,>144, <BIG_TOP,>BIG_TOP
  .byte 1, $00,$4E, <144,>144, <BIG_BOT,>BIG_BOT
  .byte 2, $00,$6D, <144,>144, $B1,0
  .byte 2, $00,$6E, <144,>144, $91,0
  .byte 1, $00,$48, <40,>40, <TILEP0,>TILEP0
  .byte 1, $00,$4B, <40,>40, <TILEP1,>TILEP1
  .byte 1, $40,$4B, <168,>168, <TILEP2,>TILEP2
  .byte 1, $00,$51, <512,>512, <FONT,>FONT
  .byte 2, $00,$71, <512,>512, $F1,0
  .byte 1, $00,$55, <144,>144, <BIG_TOP,>BIG_TOP
  .byte 1, $00,$56, <144,>144, <BIG_BOT,>BIG_BOT
  .byte 2, $00,$75, <144,>144, $B1,0
  .byte 2, $00,$76, <144,>144, $91,0
  .byte 1, $00,$50, <40,>40, <TILEP0,>TILEP0
  .byte 1, $00,$53, <40,>40, <TILEP1,>TILEP1
  .byte 1, $40,$53, <168,>168, <TILEP2,>TILEP2
  .byte 2, $00,$78, <768,>768, $20,0
  .byte 0
; tile colours to load with the hull colour: first tile, tiles, source
TCOL_LIST:
  .byte 0, 5
  .word TILEC0
  .byte 96, 5
  .word TILEC1
  .byte 104, 21
  .word TILEC2
  .byte $FF
