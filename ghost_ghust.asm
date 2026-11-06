;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;                                                              ;
;   GHOST & GHUST  -  an original single-screen platform game  ;
;   65C02 assembly, TMS9918A Graphics II (tiles + sprites)     ;
;                                                              ;
;   - Ghost and Ghust (2 players at the same time), two kind   ;
;     little ghosts, take back their abandoned villa room by   ;
;     room, from the cellar up to the tower: 30 rooms          ;
;   - shoot a round cloud at a creature: it is shut inside and ;
;     the cloud floats up to the ceiling; touch the cloud to   ;
;     pop it and the creature falls as a sweet to pick up.     ;
;     Clouds that touch pop together: 1000, 2000, 4000, 8000.  ;
;     Left too long in a cloud, a creature gets out angry.     ;
;     Jump on a cloud with the button held to bounce on it     ;
;   - bats, spiders, pumpkins, candles that throw flames,      ;
;     armours (the first cloud only knocks the helmet off)     ;
;   - G H O S T in floating clouds: all five = a life more     ;
;     each; a lantern makes the clouds faster, a bell stops    ;
;     the creatures for a while                                ;
;   - dawdle in a room and the sun rises: its ray hunts the    ;
;     ghosts until the room is clear                           ;
;   - the walls close the sides; who falls through the hole in ;
;     the floor comes back from the hole in the ceiling        ;
;   - joystick LEFT / RIGHT = float along, button 1 = cloud,   ;
;     button 2 or UP = jump (up through the platforms). 1      ;
;     player (both joysticks drive Ghost) or 2 at the same     ;
;     time (joystick 1 Ghost, joystick 2 Ghust)                ;
;   - 3 lives each, one more at 30000; a room with no life     ;
;     lost 1000; after the tower the villa starts again faster ;
;   - records: the 8 best scores, signed with 3 initials, kept ;
;     on the SD with the BIOS KEYB/SD (zone 31 of the save     ;
;     area, lib_records.asm)                                   ;
;   - SOUND (2 x AY-3-8910, played from the NMI at 60 Hz):     ;
;     a music-box waltz at the title, tunes at every room;     ;
;     Ghost's sounds on the left, Ghust's on the right         ;
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
ROOM        = $40      ; room 0-29
LOOPN       = $41      ; round of the villa (0 = first)
XGOT        = $42      ; 2 bytes: 1 = the extra life at 30000 was given
GSTATE      = $44      ; 0 playing, 1 the room is clear
GT          = $45      ; timer of GSTATE
NLEFT       = $46      ; creatures still free or shut in a cloud
LETTERS     = $47      ; G H O S T taken (bits 0-4)
ROOMT       = $48      ; seconds in the room
ROOMF       = $49      ; frames of the second
DAWN        = $4A      ; 1 = the sun is up
GATHER      = $4B      ; where the clouds gather under the ceiling (x)
HUDD        = $4C      ; to draw again: 1 scores, 2 lives, 4 letters
LETT        = $4D      ; seconds to the next letter cloud
BELLT       = $4E      ; frames the creatures stay still (bell)
LAMP        = $4F      ; 1 = faster clouds in this room (lantern)
NOLOSS      = $50      ; 2 bytes: 1 = the player lost no life in this room
SPDBASE     = $52      ; speed level the creatures start with
ROOMTOT     = $53      ; rooms reached in the game (records)
NPOP        = $54      ; creatures popped in this chain
FLOOR       = $55      ; floor of the villa 0-5 (the tiles)
TW          = $56      ; tiles of the floor: wall, platform, ceiling, window
TP_         = $57
TC          = $58
TWIN        = $59
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
HITR        = $74      ; a tile: row
HITC        = $75      ;         column
JOYC        = $76      ; 2 bytes: the joystick of every player
JOYP        = $78      ; 2 bytes: the same, the frame before
CHG         = $7A      ; 1 = a cloud was marked in the last pass of the chain
P_JOY       = $80      ; 2 bytes (joystick, 1 = pressed)
PTS_L       = $82      ; points to add (BCD)
PTS_M       = $83
PTS_H       = $84
SATB        = $85      ; bytes of the SAT to copy
HOFF        = $86      ; name table of NT_XY and CLEAR_NT (always 0 here)
RR          = $87      ; first object in the SAT (turns)
LOSTN       = $88      ; lives lost (tests)
DEATH       = $89      ; what took the last life (kind, tests)
POPS        = $8A      ; creatures popped (tests)

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

; ---------------- the players: one byte per player (0 Ghost, 1 Ghust) ----------------
P_X        = $0200       ; left x
P_XF       = $0202
P_Y        = $0204       ; top y
P_YF       = $0206
P_VXL      = $0208       ; speeds 8.8 (signed)
P_VXH      = $020A
P_VYL      = $020C
P_VYH      = $020E
P_ST       = $0210       ; 0 out, 1 on a platform, 2 in the air, 3 hit (falls away), 4 waits to come back
P_DIR      = $0212       ; 0 right, 1 left
P_T        = $0214       ; timer
P_INV      = $0216       ; frames he cannot be hit (blinks)
P_FT       = $0218       ; frames before the next cloud

; ---------------- creatures and things: 12 slots ----------------
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
O_S        = $02AC       ; state: 0 on a platform, 1 in the air
O_T        = $02B8       ; timer
O_LV       = $02C4       ; speed level 0-7 (angry: higher)
O_H        = $02D0       ; armour: 1 = helmet on; sweet: its kind
O_D        = $02DC       ; 0 right, 1 left

K_BAT      = 1
K_SPIDER   = 2
K_PUMPKIN  = 3
K_CANDLE   = 4
K_ARMOUR   = 5
K_FLAME    = 6
K_SUN      = 7
K_SWEET    = 8
K_PUFF     = 9

; ---------------- the clouds: 8 slots ----------------
NCL        = 8
C_K        = $0300       ; 0 free, 1 empty, 2 a creature inside, 3 a letter; +$80 = to pop
C_X        = $0308
C_XF       = $0310
C_Y        = $0318
C_YF       = $0320
C_VXL      = $0328
C_VXH      = $0330
C_S        = $0338       ; 0 thrown, 1 rising, 2 under the ceiling
C_T        = $0340       ; life left (4-frame units)
C_E        = $0348       ; the creature inside (kind) / the letter (0-4)
C_EL       = $0350       ; its level
C_OWN      = $0358       ; who threw it

; ---------------- other RAM ----------------
MAP        = $0800       ; the name table (rows 0-23), for the collisions
SAT_BUFFER = $0600       ; 32 sprites x 4 + end of list

; ---------------- parameters ----------------
BTN_MASK    = %00110000
JUMP_H      = $FC        ; jump: -3.5 pixels a frame
JUMP_L      = $80
GRAV        = $28        ; gravity: 0.156 pixels a frame each frame
FALL_MAX    = $01        ; ghosts float down at 1.5 pixels a frame at most
FALL_MAXL   = $80
FLOOR_Y     = 168        ; top y of who stands on the floor (row 23)
X_MIN       = 16         ; the walls
X_MAX       = 224
Y_MIN       = 24         ; under the ceiling
DAWN_S      = 40         ; seconds before the sun rises

; ---------------- records on the SD (lib_records.asm) ----------------
REC_ZONE    = 31         ; fixed zone of the game in the save area
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
;  TITLE: the name, the ghosts, the creatures
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

; one frame of the title: the ghosts wave their tails;
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
  LDA SATB                     ; the sprites are there: the tails move
  CMP #2
  BCC .tf_e
  LDA FRAME_CNT
  AND #16
  LSR A
  LSR A
  STA T0
  CLC
  ADC #PT_GH1
  STA SAT_BUFFER+2
  LDA T0
  CLC
  ADC #PT_GHL1
  STA SAT_BUFFER+6
.tf_e:
  JMP VDP_INT_ON


; ===============================================================
;  NEW GAME: room 1, 3 lives each
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
  STZ ROOM
  STZ LOOPN
  STZ LOSTN
  STZ POPS
  STZ ROOMTOT
  STZ LETTERS
  STZ RR
  ; fall into ROOM_START


; ===============================================================
;  A ROOM
; ===============================================================
ROOM_START:
  LDX #$FF
  TXS
  JSR HIDE_SPRITES
  JSR VDP_INT_OFF
  LDA #$82                     ; display off while the room is drawn
  STA VREG
  LDA #(VDP_REGISTER_BITS | 1)
  STA VREG
  LDA ROOMTOT
  CMP #99
  BCS .rs_d
  INC ROOMTOT
.rs_d:
  JSR DRAW_ROOM
  JSR DRAW_HUD
  JSR ROOM_INIT
  JSR MSG_ROOM
  JSR BUILD_SAT
  JSR VDP_INT_ON               ; (display on)
  LDA #1                       ; the tune of a new room
  STA SONG
  LDA #CMD_START
  STA SND_CMD
  LDA #20
  JSR WAIT_FRAMES
.rs_t:
  LDA #1
  JSR WAIT_FRAMES
  LDA SND_BUSY
  BNE .rs_t
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
  JSR READ_JOY
  JSR NEXT_RND
  LDA NPL                      ; the joysticks: 1 player = both drive Ghost
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
  JSR CLOUDS
  JSR OBJECTS
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
  JMP ROOM_CLEAR
.gl_go:
  JMP GAME_OVER


; ===============================================================
;  THE ROOM IS CLEAR: bonus, the next room, back home after 30
; ===============================================================
ROOM_CLEAR:
  JSR HIDE_SPRITES
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
  LDX #1                       ; no life lost in the room: 1000
.rc_nl:
  LDA P_ST,X
  BEQ .rc_nn
  LDA NOLOSS,X
  BEQ .rc_nn
  STX CI
  LDA #$00
  LDY #$10
  JSR ADD_PTS_CI
  LDX CI
.rc_nn:
  DEX
  BPL .rc_nl
  JSR UPDATE_HUD
  JSR VDP_INT_ON
.rc_t:
  LDA #1
  JSR WAIT_FRAMES
  LDA SND_BUSY
  BNE .rc_t
  LDA #40
  JSR WAIT_FRAMES
  INC ROOM                     ; the next room; after the tower, home and again
  LDA ROOM
  CMP #30
  BCC .rc_n
  STZ ROOM
  JSR HOME
.rc_n:
  JMP ROOM_START

; back home after the tower: the tune, a faster villa
HOME:
  JSR VDP_INT_OFF
  JSR MSG_CLEAR
  LDA #<TXT_HOME
  STA TP
  LDA #>TXT_HOME
  STA TP+1
  JSR PRINT
  JSR VDP_INT_ON
  LDA #3
  STA SONG
  LDA #CMD_START
  STA SND_CMD
  LDA #20
  JSR WAIT_FRAMES
.ho_t:
  LDA #1
  JSR WAIT_FRAMES
  LDA SND_BUSY
  BNE .ho_t
  LDA #60
  JSR WAIT_FRAMES
  LDA LOOPN
  CMP #9
  BCS .ho_r
  INC LOOPN
.ho_r:
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
  LDA ROOMTOT                  ; extra byte: the rooms reached
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
REC_NAME:  .byte "GHOST & GHUST   "
REC_HEAD:  .byte "BEST GHOSTS",0
REC_XLBL:  .byte "ROOM ",0


; ===============================================================
;  THE ROOM ON THE SCREEN, MESSAGES
; ===============================================================
; MAP and the name table: rows 0-1 spaces, rows 2-23 the room ROOM (interrupt off)
DRAW_ROOM:
  LDA ROOM                     ; the floor: 5 rooms each
  LDX #0
.dr_f:
  CMP #5
  BCC .dr_t
  SBC #5
  INX
  BRA .dr_f
.dr_t:
  STX FLOOR
  TXA
  ASL A
  ASL A
  CLC
  ADC #96
  STA TW                       ; wall, platform, ceiling, window
  INC A
  STA TP_
  INC A
  STA TC
  INC A
  STA TWIN
  LDX #0                       ; empty MAP: rows 0-1 spaces, the rest black (tile 0)
  LDA #0
.dr_c:
  STA MAP,X
  STA MAP+$100,X
  STA MAP+$200,X
  INX
  BNE .dr_c
  LDA #$20
  LDX #63
.dr_s:
  STA MAP,X
  DEX
  BPL .dr_s
  LDX #2                       ; the walls (columns 0-1, 30-31), a window on each side
.dr_wl:
  STX HITR
  JSR ROW_PTR
  LDA TW
  LDY #0
  STA (PTR),Y
  INY
  STA (PTR),Y
  LDY #30
  STA (PTR),Y
  INY
  STA (PTR),Y
  INX
  CPX #24
  BNE .dr_wl
  LDA TWIN
  STA MAP+5*32
  STA MAP+5*32+1
  STA MAP+5*32+30
  STA MAP+5*32+31
  STA MAP+6*32
  STA MAP+6*32+1
  STA MAP+6*32+30
  STA MAP+6*32+31
  LDX #2                       ; ceiling and floor with the hole at columns 13-18
.dr_cf:
  CPX #13
  BCC .dr_cw
  CPX #19
  BCC .dr_cn
.dr_cw:
  LDA TC
  STA MAP+2*32,X
  STA MAP+23*32,X
.dr_cn:
  INX
  CPX #30
  BNE .dr_cf
  LDX ROOM                     ; the platforms: 4 masks, mirrored
  LDA RM_LO,X
  STA PTR2
  LDA RM_HI,X
  STA PTR2+1
  LDY #0
.dr_pr:
  LDA (PTR2),Y
  STA T3                       ; the mask
  LDA PROW,Y
  TAX
  PHY
  STX HITR
  JSR ROW_PTR
  LDY #2                       ; column of block 0
.dr_b:
  LSR T3
  BCC .dr_bn
  LDA TP_
  STA (PTR),Y
  INY
  STA (PTR),Y
  DEY
  STY T4                       ; the mirror: 30 - c and 31 - c
  LDA #30
  SEC
  SBC T4
  TAY
  LDA TP_
  STA (PTR),Y
  INY
  STA (PTR),Y
  LDY T4
.dr_bn:
  INY
  INY
  CPY #16
  BNE .dr_b
  PLY
  INY
  CPY #4
  BNE .dr_pr
  LDA (PTR2),Y                 ; where the clouds gather
  STA GATHER
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
.dr_v:
  LDA (PTR),Y
  STA VDATA
  INY
  BNE .dr_v
  INC PTR+1
  DEX
  BNE .dr_v
  RTS

; HITR = row: PTR = its row of MAP (keeps X)
ROW_PTR:
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
  RTS

; X = row: the row of MAP to the name table again (interrupt off)
PUT_MAPROW:
  STX HITR
  LDY #0
  JSR NT_XY
  JSR ROW_PTR
  LDY #0
.pm_c:
  LDA (PTR),Y
  STA VDATA
  INY
  CPY #32
  BNE .pm_c
  RTS

; ROOM n and the floor on rows 9 and 13
MSG_ROOM:
  LDA #<TXT_ROOM
  STA TP
  LDA #>TXT_ROOM
  STA TP+1
  JSR PRINT
  LDA ROOM
  INC A
  JSR PUT_NUM
  LDX #13                      ; the name of the floor
  LDY #10
  JSR NT_XY
  LDA FLOOR
  ASL A
  ASL A
  STA T0
  ASL A
  ADC T0
  TAX
  LDY #12
.mr_n:
  LDA FLOOR_TXT,X
  STA VDATA
  INX
  DEY
  BNE .mr_n
  RTS

; the rows of the messages back to the room
MSG_CLEAR:
  LDX #9
  JSR PUT_MAPROW
  LDX #13
  JMP PUT_MAPROW


; ===============================================================
;  HUD: rows 0-1 (names, room, letters, scores, lives, record)
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

; X = player: his lives on row 1 (5 places, a little ghost each)
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

; row 0: ROOM nn and the letters G H O S T (a dot for the ones still missing)
DRAW_ROOMNO:
  LDX #0
  LDY #6
  JSR NT_XY
  LDX #0
.dn_s:
  LDA TXT_ROOMH,X
  STA VDATA
  INX
  CPX #5
  BNE .dn_s
  LDA ROOM
  INC A
  JSR PUT_NUM
  LDA #$20
  STA VDATA
DRAW_LETTERS:
  LDX #0
  LDY #18
  JSR NT_XY
  LDX #0
  LDA LETTERS
  STA T0
.dg_l:
  LDA #125
  LSR T0
  BCC .dg_w
  LDA GHOST_TXT,X
.dg_w:
  STA VDATA
  INX
  CPX #5
  BNE .dg_l
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
  LDX #0
  JSR DRAW_LIVES
  LDA NPL
  CMP #2
  BNE .dh_b
  LDX #1
  JSR DRAW_LIVES
.dh_b:
  JMP DRAW_ROOMNO

UPDATE_HUD:                    ; HUDD bits: 1 scores, 2 lives, 4 letters
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
  JSR DRAW_LETTERS
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

; PTS_L / PTS_M / PTS_H (BCD) to the player CI; a life more at 30000
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
  CMP #$03
  BCC .as_d
  INC XGOT,X
  JSR LIFE_UP
.as_d:
  LDA #1
  TSB HUDD
  PLY
  PLX
  RTS

; X = player: a life more (at most 5)
LIFE_UP:
  LDA LIVES,X
  CMP #5
  BCS .lu_m
  INC LIVES,X
.lu_m:
  LDA #2
  TSB HUDD
  LDA #W_EXTRA
  JMP SFX_P

; A = whistle of player CI: Ghost on the left chip, Ghust on the right (keeps X, Y)
SFX_P:
  PHX
  LDX CI
  JSR SFX_WHISTLE
  PLX
  RTS

; A / Y = points (BCD) to the player CI (keeps X)
PTS_CI_X:
  PHX
  JSR ADD_PTS_CI
  PLX
  RTS


; ===============================================================
;  THE ROOM: creatures, players, timers
; ===============================================================
ROOM_INIT:
  LDX #NOB-1
.ri_o:
  STZ O_K,X
  DEX
  BPL .ri_o
  LDX #NCL-1
.ri_c:
  STZ C_K,X
  DEX
  BPL .ri_c
  STZ DAWN
  STZ ROOMT
  STZ BELLT
  STZ LAMP
  LDA #59
  STA ROOMF
  LDA #12
  STA LETT
  LDA FLOOR                    ; the creatures get faster with the floor and the round
  LSR A
  STA T0
  LDA LOOPN
  ASL A
  CLC
  ADC T0
  CMP #4
  BCC .ri_s
  LDA #4
.ri_s:
  STA SPDBASE
  STZ NLEFT
  LDX ROOM                     ; the creatures of the room: kind, platform, x
  LDA RM_LO,X
  STA PTR2
  LDA RM_HI,X
  STA PTR2+1
  LDY #5
.ri_e:
  LDA (PTR2),Y
  BEQ .ri_p
  STA T5
  INY
  LDA (PTR2),Y
  TAX
  LDA PROW,X                   ; standing on that platform
  ASL A
  ASL A
  ASL A
  SEC
  SBC #16
  STA T3
  INY
  LDA (PTR2),Y
  STA T2
  INY
  PHY
  LDA T5
  JSR NEW_CREATURE
  PLY
  BRA .ri_e
.ri_p:
  LDX #1                       ; the players with lives left: on the floor
.ri_pl:
  STZ P_ST,X
  LDA LIVES,X
  BEQ .ri_pn
  JSR PLACE_PLAYER
  LDA #1
  STA NOLOSS,X
  LDA #60
  STA P_INV,X
.ri_pn:
  DEX
  BPL .ri_pl
  RTS

; X = player: on the floor at his place, still
PLACE_PLAYER:
  LDA #1
  STA P_ST,X
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
  STZ P_FT,X
  TXA
  STA P_DIR,X                  ; Ghost looks right, Ghust left
  RTS

; A = kind, T2 = x, T3 = y: a creature (one more to clear)
NEW_CREATURE:
  JSR NEW_OBJ
  BCS .nc_r
  INC NLEFT
  LDA SPDBASE
  STA O_LV,X
  JSR NEXT_RND
  AND #3
  STA O_D,X                    ; bit 0: left, bit 1: up (bats)
  LDA O_K,X
  CMP #K_ARMOUR
  BNE .nc_t
  LDA #1                       ; an armour comes with its helmet
  STA O_H,X
.nc_t:
  JSR NEXT_RND
  AND #63
  ADC #60
  STA O_T,X
.nc_r:
  RTS

; the clock: the room clear, the bell, letters, the dawn
CLOCK:
  LDA GSTATE
  BNE .ck_r
  LDA NLEFT                    ; every creature popped: 3 s for the sweets
  BNE .ck_b
  LDA #1
  STA GSTATE
  LDA #180
  STA GT
  LDX #NOB-1                   ; the sun goes, the flames too
.ck_k:
  LDA O_K,X
  CMP #K_FLAME
  BEQ .ck_kk
  CMP #K_SUN
  BNE .ck_kn
.ck_kk:
  STZ O_K,X
.ck_kn:
  DEX
  BPL .ck_k
.ck_r:
  RTS
.ck_b:
  LDA BELLT
  BEQ .ck_s
  DEC BELLT
.ck_s:
  DEC ROOMF                    ; ---- once a second
  BPL .ck_r
  LDA #59
  STA ROOMF
  INC ROOMT
  LDA LETTERS                  ; a letter cloud now and then
  CMP #$1F
  BEQ .ck_d
  DEC LETT
  BNE .ck_d
  LDA #15
  STA LETT
  JSR NEW_LETTER
.ck_d:
  LDA DAWN                     ; the dawn
  BNE .ck_r
  LDA LOOPN
  ASL A
  ASL A
  ASL A
  STA T0
  LDA #DAWN_S
  SEC
  SBC T0
  CMP #20
  BCS .ck_dc
  LDA #20
.ck_dc:
  CMP ROOMT
  BCS .ck_r
  INC DAWN
  LDA #X_MIN
  STA T2
  LDA #Y_MIN
  STA T3
  LDA #K_SUN
  JSR NEW_OBJ
  LDA #W_DAWN
  LDX #2
  JMP SFX_WHISTLE

; a cloud with a letter still missing, from the hole in the floor
NEW_LETTER:
  JSR FREE_CLOUD
  BCS .nl_r
.nl_l:
  JSR NEXT_RND                 ; a random letter still missing
  AND #7
  CMP #5
  BCS .nl_l
  TAY
  LDA BITS,Y
  AND LETTERS
  BNE .nl_l
  TYA
  STA C_E,X
  LDA #3
  STA C_K,X
  LDA #120
  STA C_X,X
  LDA #176
  STA C_Y,X
  LDA #1
  STA C_S,X
  LDA #200
  STA C_T,X
.nl_r:
  RTS

; X = a free cloud (C = 1: none)
FREE_CLOUD:
  LDX #NCL-1
.fc_l:
  LDA C_K,X
  BEQ .fc_ok
  DEX
  BPL .fc_l
  SEC
  RTS
.fc_ok:
  STZ C_XF,X
  STZ C_YF,X
  STZ C_VXL,X
  STZ C_VXH,X
  STZ C_S,X
  STZ C_EL,X
  STZ C_OWN,X
  CLC
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
  DEC P_T,X                    ; waiting: back on the floor
  BNE .pl_n
  JSR PLACE_PLAYER
  LDA #180
  STA P_INV,X
  BRA .pl_n
.pl_hit:
  JSR FALL_AWAY
  BRA .pl_n
.pl_m:
  JSR MOVE_PLAYER
  JSR SHOOT
.pl_n:
  LDX CI
  LDA P_INV,X
  BEQ .pl_f
  DEC P_INV,X
.pl_f:
  LDA P_FT,X
  BEQ .pl_x
  DEC P_FT,X
.pl_x:
  DEX
  BPL .pl_l
  RTS

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

; X = player on a platform or in the air
MOVE_PLAYER:
  STZ P_VXL,X                  ; ---- float along: 1.25 pixels a frame, the walls stop
  STZ P_VXH,X
  LDA JOYC,X
  AND #$0C
  BEQ .mp_y
  CMP #$08
  BEQ .mp_r
  CMP #$04
  BNE .mp_y
  LDA #1
  STA P_DIR,X
  SEC
  LDA P_XF,X
  SBC #$40
  STA P_XF,X
  LDA P_X,X
  SBC #1
  CMP #X_MIN
  BCS .mp_xs
  LDA #X_MIN
  BRA .mp_xs
.mp_r:
  STZ P_DIR,X
  CLC
  LDA P_XF,X
  ADC #$40
  STA P_XF,X
  LDA P_X,X
  ADC #1
  CMP #X_MAX+1
  BCC .mp_xs
  LDA #X_MAX
.mp_xs:
  STA P_X,X
  LDA #1                       ; (moving: the walk animation)
  STA P_VXL,X
.mp_y:
  LDA P_ST,X                   ; ---- on a platform: jump, or float off its end
  CMP #1
  BNE .mp_air
  LDA JOYC,X                   ; button 2 or UP
  AND #$21
  BEQ .mp_sup
  LDA JOYP,X
  AND #$21
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
  BCS .mp_ret
  LDA #2
  STA P_ST,X
  STZ P_VYL,X
  STZ P_VYH,X
.mp_ret:
  RTS
.mp_air:                       ; ---- in the air: up through the platforms, float down on them
  JSR BODY_FALL
  LDA P_VYH,X
  BPL .mp_down
  LDA P_Y,X                    ; going up: never into the ceiling
  CMP #Y_MIN
  BCS .mp_r2
  CMP #200
  BCS .mp_r2
  LDA #Y_MIN
  STA P_Y,X
  STZ P_VYL,X
  STZ P_VYH,X
  RTS
.mp_down:
  LDA P_X,X                    ; coming down: the feet on a platform
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

; X = player: gravity (down at 1.5 pixels a frame at most), y moves; through the
; hole in the floor he comes back from the top
BODY_FALL:
  CLC
  LDA P_VYL,X
  ADC #GRAV
  STA P_VYL,X
  LDA P_VYH,X
  ADC #0
  STA P_VYH,X
  BMI .bf_m
  CMP #FALL_MAX
  BCC .bf_m
  BNE .bf_c
  LDA P_VYL,X
  CMP #FALL_MAXL
  BCC .bf_m
.bf_c:
  LDA #FALL_MAXL
  STA P_VYL,X
  LDA #FALL_MAX
  STA P_VYH,X
.bf_m:
  CLC
  LDA P_YF,X
  ADC P_VYL,X
  STA P_YF,X
  LDA P_Y,X
  ADC P_VYH,X
  STA P_Y,X
  CMP #192
  BCC .bf_r
  CMP #220
  BCS .bf_r
  STZ P_Y,X                    ; out of the bottom: in from the top
.bf_r:
  RTS

; X = player: button 1 = a cloud in front of him (4 at most each)
SHOOT:
  LDA JOYC,X
  AND #$10
  BEQ .sh_r
  LDA JOYP,X
  AND #$10
  BNE .sh_r
  LDA P_FT,X
  BNE .sh_r
  LDY #NCL-1                   ; his clouds
  STZ T0
.sh_c:
  LDA C_K,Y
  BEQ .sh_cn
  LDA C_OWN,Y
  CMP CI
  BNE .sh_cn
  INC T0
.sh_cn:
  DEY
  BPL .sh_c
  LDA T0
  CMP #4
  BCS .sh_r
  JSR FREE_CLOUD
  BCS .sh_r
  LDY CI
  LDA #1
  STA C_K,X
  TYA
  STA C_OWN,X
  LDA P_Y,Y
  STA C_Y,X
  LDA #150                     ; 10 s
  STA C_T,X
  LDA LAMP                     ; 4 pixels a frame (5 with the lantern)
  CLC
  ADC #4
  STA T1
  LDA P_DIR,Y
  BNE .sh_l
  LDA P_X,Y
  CLC
  ADC #10
  STA C_X,X
  LDA T1
  STA C_VXH,X
  BRA .sh_s
.sh_l:
  LDA P_X,Y
  SEC
  SBC #10
  STA C_X,X
  LDA #0
  SEC
  SBC T1
  STA C_VXH,X
.sh_s:
  LDX CI
  LDA #12
  STA P_FT,X
  LDA #W_SHOOT
  JMP SFX_P
.sh_r:
  RTS


; ===============================================================
;  THE PLATFORMS: collisions with the tiles
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

; A = tile: C = 1 if one can stand on it (a platform, the floor)
IS_SOLID:
  CMP TP_
  BEQ .is_y
  CMP TC
  BEQ .is_y
  CLC
  RTS
.is_y:
  SEC
  RTS

; A = left x, Y = top y of a 16x16 body standing: C = 1 if a platform is under its feet
; (columns of x + 4 and x + 11, the row of y + 16) (keeps X)
SUPPORT:
  STA T6
  TYA
  CLC
  ADC #16
  CMP #192
  BCS .su_n
  TAY
  LDA T6
  JMP SUPPORT_F
.su_n:
  CLC
  RTS

; A = left x, Y = top y of a falling body: C = 1 if its feet just went into the top
; of a platform; then A = the top y standing on it (keeps X)
LANDING:
  STA T6
  TYA
  CLC
  ADC #16
  CMP #192
  BCS .ln_n
  STA T7
  AND #7
  CMP #4
  BCS .ln_n
  LDY T7
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

; A = left x, Y = feet y: C = 1 if a platform is at the feet (keeps X)
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
;  THE CLOUDS
; ===============================================================
CLOUDS:
  LDX #NCL-1
.cl_l:
  STX OI
  LDA C_K,X
  BEQ .cl_n
  JSR CLOUD_ONE
.cl_n:
  LDX OI
  DEX
  BPL .cl_l
  RTS

; X = cloud: life, flight, catch, the players
CLOUD_ONE:
  LDA FRAME_CNT                ; ---- life (4-frame units)
  AND #3
  BNE .co_m
  DEC C_T,X
  BNE .co_m
  JMP CLOUD_END
.co_m:
  LDA C_S,X
  BNE .co_up
  ; ---- thrown: forwards, slowing down; it catches a creature
  CLC
  LDA C_XF,X
  ADC C_VXL,X
  STA C_XF,X
  LDA C_X,X
  ADC C_VXH,X
  CMP #X_MIN
  BCC .co_wall
  CMP #X_MAX+1
  BCC .co_x
.co_wall:
  LDA #X_MIN                   ; against a wall: it stops there
  LDY C_VXH,X
  BMI .co_wl
  LDA #X_MAX
.co_wl:
  STA C_X,X
  BRA .co_rise
.co_x:
  STA C_X,X
  LDA C_VXH,X                  ; slow down: 0.19 pixels a frame each frame
  BMI .co_neg
  LDA C_VXL,X
  SEC
  SBC #$30
  STA C_VXL,X
  LDA C_VXH,X
  SBC #0
  STA C_VXH,X
  BMI .co_rise
  BNE .co_c
  LDA C_VXL,X
  CMP #$60
  BCC .co_rise
  BRA .co_c
.co_neg:
  LDA C_VXL,X
  CLC
  ADC #$30
  STA C_VXL,X
  LDA C_VXH,X
  ADC #0
  STA C_VXH,X
  BPL .co_rise
  CMP #$FF
  BNE .co_c
  LDA C_VXL,X
  CMP #$A0
  BCS .co_rise
.co_c:
  LDA C_K,X                    ; an empty cloud on its way catches
  CMP #1
  BNE .co_r
  JMP CATCH
.co_rise:
  LDA #1
  STA C_S,X
.co_r:
  RTS
.co_up:
  CMP #1
  BNE .co_g
  SEC                          ; ---- rising at 0.5 pixels a frame
  LDA C_YF,X
  SBC #$80
  STA C_YF,X
  LDA C_Y,X
  SBC #0
  STA C_Y,X
  CMP #Y_MIN+1
  BCS .co_p
  LDA #2
  STA C_S,X
  BRA .co_p
.co_g:
  LDA FRAME_CNT                ; ---- under the ceiling: slowly towards the gathering place
  AND #3
  BNE .co_p
  LDA C_X,X
  CMP GATHER
  BEQ .co_p
  BCC .co_gr
  DEC C_X,X
  BRA .co_p
.co_gr:
  INC C_X,X
.co_p:
  JMP CLOUD_PLAYERS

; X = cloud thrown: a creature in its way is shut inside (an armour loses its helmet)
CATCH:
  LDY #NOB-1
.ca_l:
  LDA O_K,Y
  BEQ .ca_n
  CMP #K_FLAME
  BCS .ca_n
  LDA O_X,Y
  SEC
  SBC C_X,X
  CLC
  ADC #11
  CMP #22
  BCS .ca_n
  LDA O_Y,Y
  SEC
  SBC C_Y,X
  CLC
  ADC #11
  CMP #22
  BCS .ca_n
  LDA O_K,Y
  CMP #K_ARMOUR
  BNE .ca_in
  LDA O_H,Y
  BEQ .ca_in
  LDA #0                       ; the helmet falls: the cloud bursts
  STA O_H,Y
  JMP CLOUD_PUFF
.ca_in:
  LDA O_K,Y
  STA C_E,X
  LDA O_LV,Y
  STA C_EL,X
  LDA #0
  STA O_K,Y
  LDA #2
  STA C_K,X
  STA C_S,X
  DEC C_S,X                    ; it rises at once
  LDA #150
  STA C_T,X
  PHX
  LDA C_OWN,X
  TAX
  LDA #W_CATCH
  JSR SFX_WHISTLE
  PLX
  RTS
.ca_n:
  DEY
  BPL .ca_l
  RTS

; X = cloud at the end of its life: empty or a letter: it vanishes; a creature gets out angry
CLOUD_END:
  LDA C_K,X
  CMP #2
  BNE CLOUD_PUFF
  LDA C_X,X
  STA T2
  LDA C_Y,X
  STA T3
  STZ C_K,X
  LDA C_E,X
  JSR NEW_OBJ
  BCS .ce_r
  LDY OI
  LDA C_EL,Y                   ; angry: faster
  CLC
  ADC #2
  CMP #8
  BCC .ce_l
  LDA #7
.ce_l:
  STA O_LV,X
  LDA #1
  STA O_S,X
  LDA #W_ANGRY
  LDX #1
  JSR SFX_WHISTLE
.ce_r:
  LDX OI
  RTS

; X = cloud: gone in a puff
CLOUD_PUFF:
  LDA C_X,X
  STA T2
  LDA C_Y,X
  STA T3
  STZ C_K,X
  LDA #K_PUFF
  JSR NEW_OBJ
  BCS .cp_r
  LDA #10
  STA O_T,X
.cp_r:
  LDX OI
  RTS

; X = cloud risen: a player touches it: he pops it, or bounces on it with the jump held
CLOUD_PLAYERS:
  LDY #1
.cpl_l:
  LDA P_ST,Y
  BEQ .cpl_n
  CMP #3
  BCS .cpl_n
  LDA P_X,Y
  SEC
  SBC C_X,X
  CLC
  ADC #13
  CMP #26
  BCS .cpl_n
  LDA P_Y,Y
  SEC
  SBC C_Y,X
  CLC
  ADC #13
  CMP #26
  BCS .cpl_n
  STY CI
  LDA P_VYH,Y                  ; coming down on top with the jump held: a bounce
  BMI .cpl_p
  LDA C_Y,X
  SEC
  SBC P_Y,Y
  CMP #6
  BCC .cpl_p
  LDA JOYC,Y
  AND #$21
  BEQ .cpl_p
  LDA #JUMP_L
  STA P_VYL,Y
  LDA #JUMP_H
  STA P_VYH,Y
  LDA #2
  STA P_ST,Y
  RTS
.cpl_p:
  JMP POP_CHAIN
.cpl_n:
  DEY
  BPL .cpl_l
  RTS

; X = cloud touched by the player CI: it pops, and every cloud touching a popping one
POP_CHAIN:
  LDA C_K,X
  ORA #$80
  STA C_K,X
.pc_pass:
  STZ CHG
  LDX #NCL-1
.pc_a:
  LDA C_K,X
  BPL .pc_an
  LDY #NCL-1
.pc_b:
  LDA C_K,Y
  BEQ .pc_bn
  BMI .pc_bn
  LDA C_S,Y                    ; (not the ones still thrown)
  BEQ .pc_bn
  LDA C_X,Y
  SEC
  SBC C_X,X
  CLC
  ADC #18
  CMP #36
  BCS .pc_bn
  LDA C_Y,Y
  SEC
  SBC C_Y,X
  CLC
  ADC #18
  CMP #36
  BCS .pc_bn
  LDA C_K,Y
  ORA #$80
  STA C_K,Y
  INC CHG
.pc_bn:
  DEY
  BPL .pc_b
.pc_an:
  DEX
  BPL .pc_a
  LDA CHG
  BNE .pc_pass
  STZ NPOP                     ; ---- every marked cloud pops
  LDX #NCL-1
.pc_p:
  LDA C_K,X
  BPL .pc_pn
  STX OI
  JSR POP_ONE
  LDX OI
.pc_pn:
  DEX
  BPL .pc_p
  LDA #W_POP
  JSR SFX_P
  LDA #S_POP
  LDY C_X
  LDX CI
  JMP SFX_BOOM

; X = a popping cloud
POP_ONE:
  LDA C_K,X
  AND #$7F
  CMP #2
  BEQ .po_c
  CMP #3
  BEQ .po_l
  LDA #$10                     ; empty: 10
  LDY #$00
  JSR PTS_CI_X
  JMP CLOUD_PUFF
.po_l:
  LDY C_E,X                    ; a letter
  LDA BITS,Y
  TSB LETTERS
  LDA #4
  TSB HUDD
  PHX
  LDA #W_LETTER
  JSR SFX_P
  PLX
  LDA LETTERS
  CMP #$1F
  BNE .po_lp
  STZ LETTERS                  ; G H O S T: a life more each
  PHX
  LDX #1
.po_lu:
  LDA P_ST,X
  BEQ .po_ln
  JSR LIFE_UP
.po_ln:
  DEX
  BPL .po_lu
  PLX
.po_lp:
  JMP CLOUD_PUFF
.po_c:
  LDY NPOP                     ; a creature: 1000, 2000, 4000, 8000 in the chain
  CPY #3
  BCC .po_pt
  LDY #3
.po_pt:
  LDA POPPTS,Y
  TAY
  LDA #$00
  JSR PTS_CI_X
  INC NPOP
  INC POPS
  DEC NLEFT
  LDA C_X,X                    ; it falls as a sweet
  STA T2
  LDA C_Y,X
  STA T3
  LDA C_E,X
  STA T4
  STZ C_K,X
  LDA #K_SWEET
  JSR NEW_OBJ
  BCS .po_r
  LDA T4                       ; the sweet of the creature; a chain of 2 the lantern, 3 the bell
  DEC A
  CMP #3
  BCC .po_sw
  SEC
  SBC #3
.po_sw:
  LDY NPOP
  CPY #2
  BNE .po_s3
  LDA #3
.po_s3:
  CPY #3
  BNE .po_s
  LDA #4
.po_s:
  STA O_H,X
  LDA #240
  STA O_T,X
  LDA #1
  STA O_S,X
.po_r:
  LDX OI
  RTS


; ===============================================================
;  CREATURES AND THINGS
; ===============================================================
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

OBJECTS:
  LDX #NOB-1
.ob_l:
  STX OI
  LDA O_K,X
  BEQ .ob_n
  CMP #K_FLAME
  BCS .ob_t
  LDY BELLT                    ; the bell: the creatures stand still
  BNE .ob_n
  CMP #K_BAT
  BNE .ob_w
  JSR BAT
  BRA .ob_n
.ob_w:
  JSR WALKER
  BRA .ob_n
.ob_t:
  CMP #K_FLAME
  BNE .ob_s
  JSR FLAME
  BRA .ob_n
.ob_s:
  CMP #K_SUN
  BNE .ob_sw
  JSR SUN
  BRA .ob_n
.ob_sw:
  CMP #K_SWEET
  BNE .ob_p
  JSR SWEET
  BRA .ob_n
.ob_p:
  DEC O_T,X                    ; a puff goes away
  BNE .ob_n
  STZ O_K,X
.ob_n:
  LDX OI
  DEX
  BPL .ob_l
  RTS

; X = creature: Y = its speed level (0-7), T0 = the fraction, T1 = the pixels
SPEED_OF:
  LDY O_LV,X
  LDA NLEFT                    ; the last one runs at the top speed
  CMP #1
  BNE .so_v
  LDY #7
.so_v:
  LDA SPD_L,Y
  STA T0
  LDA SPD_H,Y
  STA T1
  RTS

; ---------------------------------------------------------------
; a bat: flies on the slant, bounces on the walls, the ceiling, the floor
; ---------------------------------------------------------------
BAT:
  JSR SPEED_OF
  LDA O_D,X
  AND #1
  BNE .ba_l
  CLC
  LDA O_XF,X
  ADC T0
  STA O_XF,X
  LDA O_X,X
  ADC T1
  CMP #X_MAX
  BCC .ba_xs
  LDA #X_MAX
  BRA .ba_xb
.ba_l:
  SEC
  LDA O_XF,X
  SBC T0
  STA O_XF,X
  LDA O_X,X
  SBC T1
  CMP #X_MIN
  BCS .ba_xs
  LDA #X_MIN
.ba_xb:
  STA O_X,X
  LDA O_D,X                    ; a wall: the other way
  EOR #1
  STA O_D,X
  BRA .ba_y
.ba_xs:
  STA O_X,X
.ba_y:
  LSR T1                       ; up and down at half the speed
  ROR T0
  LDA O_D,X
  AND #2
  BNE .ba_u
  CLC
  LDA O_YF,X
  ADC T0
  STA O_YF,X
  LDA O_Y,X
  ADC T1
  CMP #FLOOR_Y
  BCC .ba_ys
  LDA #FLOOR_Y
  BRA .ba_yb
.ba_u:
  SEC
  LDA O_YF,X
  SBC T0
  STA O_YF,X
  LDA O_Y,X
  SBC T1
  CMP #Y_MIN
  BCS .ba_ys
  LDA #Y_MIN
.ba_yb:
  STA O_Y,X
  LDA O_D,X
  EOR #2
  STA O_D,X
  RTS
.ba_ys:
  STA O_Y,X
  RTS

; ---------------------------------------------------------------
; spiders, candles, armours walk; pumpkins hop; they jump up after a ghost above
; ---------------------------------------------------------------
WALKER:
  LDA O_S,X
  BEQ .wk_g
  JMP WK_AIR
.wk_g:
  JSR WALK_X
  LDA O_K,X                    ; a pumpkin hops all the time
  CMP #K_PUMPKIN
  BNE .wk_j
  LDA #$80
  STA O_VYL,X
  LDA #$FD
  STA O_VYH,X
  LDA #1
  STA O_S,X
  RTS
.wk_j:
  DEC O_T,X                    ; now and then: up after a ghost above, or a flame
  BNE .wk_s
  JSR NEXT_RND
  AND #63
  ADC #50
  STA O_T,X
  LDA O_K,X
  CMP #K_CANDLE
  BNE .wk_up
  JSR CANDLE_FIRE
.wk_up:
  JSR GHOST_ABOVE
  BCC .wk_s
  LDA #JUMP_L
  STA O_VYL,X
  LDA #JUMP_H
  STA O_VYH,X
  LDA #1
  STA O_S,X
  RTS
.wk_s:
  LDA O_X,X                    ; nothing under the feet: it falls
  LDY O_Y,X
  JSR SUPPORT
  BCS .wk_r
  LDA #1
  STA O_S,X
  STZ O_VYL,X
  STZ O_VYH,X
.wk_r:
  RTS

WK_AIR:
  JSR WALK_X
  CLC                          ; gravity, down at 2 pixels a frame at most
  LDA O_VYL,X
  ADC #GRAV
  STA O_VYL,X
  LDA O_VYH,X
  ADC #0
  CMP #2
  BMI .wa_v
  LDA #2
  STZ O_VYL,X
.wa_v:
  STA O_VYH,X
  CLC
  LDA O_YF,X
  ADC O_VYL,X
  STA O_YF,X
  LDA O_Y,X
  ADC O_VYH,X
  STA O_Y,X
  CMP #192                     ; out of the bottom: in from the top
  BCC .wa_t
  CMP #220
  BCS .wa_t
  STZ O_Y,X
  RTS
.wa_t:
  LDA O_VYH,X
  BMI .wa_c
  LDA O_X,X
  LDY O_Y,X
  JSR LANDING
  BCC .wa_r
  STA O_Y,X
  STZ O_YF,X
  STZ O_VYL,X
  STZ O_VYH,X
  STZ O_S,X
.wa_r:
  RTS
.wa_c:
  LDA O_Y,X                    ; going up: never into the ceiling
  CMP #Y_MIN
  BCS .wa_r
  LDA #Y_MIN
  STA O_Y,X
  STZ O_VYL,X
  STZ O_VYH,X
  RTS

; X = walker: a step along its way; a wall turns it back
WALK_X:
  JSR SPEED_OF
  LDA O_D,X
  AND #1
  BNE .wx_l
  CLC
  LDA O_XF,X
  ADC T0
  STA O_XF,X
  LDA O_X,X
  ADC T1
  CMP #X_MAX
  BCC .wx_s
  LDA #X_MAX
  BRA .wx_t
.wx_l:
  SEC
  LDA O_XF,X
  SBC T0
  STA O_XF,X
  LDA O_X,X
  SBC T1
  CMP #X_MIN
  BCS .wx_s
  LDA #X_MIN
.wx_t:
  STA O_X,X
  LDA O_D,X
  EOR #1
  STA O_D,X
  RTS
.wx_s:
  STA O_X,X
  RTS

; X = creature: C = 1 if a ghost is above it (higher by 20 pixels or more), not far aside
GHOST_ABOVE:
  LDY #1
.ga_l:
  LDA P_ST,Y
  BEQ .ga_n
  CMP #3
  BCS .ga_n
  LDA O_Y,X
  SEC
  SBC P_Y,Y
  CMP #20
  BCC .ga_n
  CMP #100
  BCS .ga_n
  LDA P_X,Y
  SEC
  SBC O_X,X
  CLC
  ADC #48
  CMP #96
  BCC .ga_y
.ga_n:
  DEY
  BPL .ga_l
  CLC
  RTS
.ga_y:
  SEC
  RTS

; X = candle: a flame forwards if a ghost is at its height
CANDLE_FIRE:
  LDY #1
.cf_l:
  LDA P_ST,Y
  BEQ .cf_n
  CMP #3
  BCS .cf_n
  LDA P_Y,Y
  SEC
  SBC O_Y,X
  CLC
  ADC #10
  CMP #20
  BCC .cf_f
.cf_n:
  DEY
  BPL .cf_l
  RTS
.cf_f:
  LDA P_X,Y                    ; it turns to the ghost and fires
  CMP O_X,X
  LDA #0
  BCS .cf_d
  LDA #1
.cf_d:
  STA O_D,X
  STA T4
  LDA O_X,X
  STA T2
  LDA O_Y,X
  STA T3
  PHX
  LDA #K_FLAME
  JSR NEW_OBJ
  BCS .cf_x
  LDA T4
  STA O_D,X
  LDA #120
  STA O_T,X
  LDA #W_FLAME
  LDX #1
  JSR SFX_WHISTLE
.cf_x:
  PLX
  RTS

; a flame: straight on at 2 pixels a frame until a wall
FLAME:
  LDA O_D,X
  BNE .fl_l
  LDA O_X,X
  CLC
  ADC #2
  CMP #X_MAX+8
  BCS .fl_k
  STA O_X,X
  RTS
.fl_l:
  LDA O_X,X
  SEC
  SBC #2
  CMP #X_MIN-8
  BCC .fl_k
  STA O_X,X
  RTS
.fl_k:
  STZ O_K,X
  RTS

; the sun of the dawn: it comes after the nearest ghost, through everything
SUN:
  LDY #0                       ; the ghost to follow: Ghost, or Ghust if Ghost is not there
  LDA P_ST
  BEQ .su_1
  CMP #3
  BCC .su_go
.su_1:
  INY
  LDA P_ST,Y
  BEQ .su_r
  CMP #3
  BCS .su_r
.su_go:
  LDA #$A0                     ; 0.6 pixels a frame each way (faster in the next rounds)
  CLC
  ADC LOOPN
  ADC LOOPN
  STA T0
  LDA P_X,Y
  CMP O_X,X
  BEQ .su_y
  BCC .su_xl
  CLC
  LDA O_XF,X
  ADC T0
  STA O_XF,X
  BCC .su_y
  INC O_X,X
  BRA .su_y
.su_xl:
  SEC
  LDA O_XF,X
  SBC T0
  STA O_XF,X
  BCS .su_y
  DEC O_X,X
.su_y:
  LDA P_Y,Y
  CMP O_Y,X
  BEQ .su_r
  BCC .su_yu
  CLC
  LDA O_YF,X
  ADC T0
  STA O_YF,X
  BCC .su_r
  INC O_Y,X
  RTS
.su_yu:
  SEC
  LDA O_YF,X
  SBC T0
  STA O_YF,X
  BCS .su_r
  DEC O_Y,X
.su_r:
  RTS

; a sweet: falls on a platform, stays a while
SWEET:
  DEC O_T,X
  BNE .sw_f
  STZ O_K,X
  RTS
.sw_f:
  LDA O_S,X
  BEQ .sw_r
  LDA O_Y,X
  CLC
  ADC #2
  STA O_Y,X
  CMP #192
  BCC .sw_l
  STZ O_K,X
  RTS
.sw_l:
  LDA O_X,X
  LDY O_Y,X
  JSR LANDING
  BCC .sw_r
  STA O_Y,X
  STZ O_S,X
.sw_r:
  RTS


; ===============================================================
;  TOUCHES: the players against the creatures and the things
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
  LDA O_X,Y                    ; 11 pixels apart at most
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
  CMP #K_SWEET
  BNE .tc_e
  STZ O_K,X                    ; a sweet: points, the lantern, the bell
  LDY O_H,X
  CPY #3
  BCC .tc_pt
  BEQ .tc_lamp
  LDA #240                     ; the bell: 4 s of rest
  STA BELLT
  BRA .tc_snd
.tc_lamp:
  LDA #1
  STA LAMP
  BRA .tc_snd
.tc_pt:
  LDA SWEETPTS,Y
  TAY
  LDA #$00
  JSR ADD_PTS_CI
.tc_snd:
  LDA #W_CANDY
  JMP SFX_P
.tc_e:
  CMP #K_FLAME                 ; a creature standing still under the bell does no harm
  BCS TC_HIT
  LDA BELLT
  BEQ TC_HIT
  RTS
TC_HIT:                        ; a creature, a flame, the sun (global: the tests)
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
;  SPRITES: the players, the clouds and the objects take turns
; ===============================================================
BUILD_SAT:
  STZ SPRI
  LDA FRAME_CNT
  AND #1
  BEQ .bs_p
  JSR SAT_OBJS
  JSR SAT_CLOUDS
  JSR SAT_PLAYERS
  BRA .bs_e
.bs_p:
  JSR SAT_PLAYERS
  JSR SAT_CLOUDS
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
  LDA #PT_GHD
  BRA .sp_put
.sp_a:
  LDA FRAME_CNT                ; the tail waves (faster when moving)
  LDY P_VXL,X
  BEQ .sp_w
  ASL A
.sp_w:
  AND #16
  LSR A
  LSR A
  CLC
  ADC #PT_GH1
  LDY P_DIR,X
  BEQ .sp_put
  CLC
  ADC #PT_GHL1-PT_GH1
.sp_put:
  STA ON
  JSR ADD_SPR
.sp_n:
  DEX
  BPL .sp_l
  RTS

SAT_CLOUDS:
  LDX #NCL-1
.sc_l:
  LDA C_K,X
  BEQ .sc_n
  LDA C_X,X
  STA OX
  LDA C_Y,X
  STA OY
  LDA C_K,X
  CMP #2
  BEQ .sc_e
  BCS .sc_le
  LDA #PT_CLOUD                ; empty: the colour of who threw it
  STA ON
  LDY C_OWN,X
  LDA PCOL,Y
  BRA .sc_c
.sc_le:
  LDA C_E,X                    ; a letter: yellow
  ASL A
  ASL A
  CLC
  ADC #PT_LG
  STA ON
  LDA #11
  BRA .sc_c
.sc_e:
  LDA #PT_CLOUDE               ; a creature inside: its colour, red when it is about to get out
  STA ON
  LDY C_E,X
  LDA KCOL,Y
  LDY C_T,X
  CPY #24
  BCS .sc_c
  LDY FRAME_CNT
  CPY #128
  BCC .sc_c
  LDA #8
.sc_c:
  STA OC
  JSR ADD_SPR
.sc_n:
  DEX
  BPL .sc_l
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
  LDY O_K,X
  LDA KCOL,Y
  STA OC
  CPY #K_FLAME                 ; creatures: red when angry
  BCS .ol_k
  LDA O_LV,X
  SEC
  SBC SPDBASE
  CMP #2
  BCC .ol_k
  CMP #8
  BCS .ol_k
  LDA #8
  STA OC
.ol_k:
  LDA FRAME_CNT                ; 2 pictures: T0 = 0 / 4
  AND #8
  LSR A
  STA T0
  LDA KPAT,Y
  CPY #K_CANDLE
  BNE .ol_a
  LDY O_D,X                    ; a candle looks where it goes
  BEQ .ol_2
  LDA #PT_CANL1
  BRA .ol_2
.ol_a:
  CPY #K_ARMOUR
  BNE .ol_sw
  LDY O_H,X
  BNE .ol_2
  LDA #PT_ARMH                 ; without its helmet
  BRA .ol_put
.ol_sw:
  CPY #K_SWEET
  BNE .ol_f
  LDY O_H,X                    ; the sweet of its kind
  LDA SWCOL,Y
  STA OC
  LDA SWPAT,Y
  BRA .ol_put
.ol_f:
  CPY #K_FLAME
  BEQ .ol_put
  CPY #K_PUFF
  BEQ .ol_put
.ol_2:
  CLC
  ADC T0
.ol_put:
  STA ON
  RTS


; ===============================================================
;  SCREEN: VRAM, texts, sprites, sound (from super carlo)
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
SC_COL:     .byte 0,26                         ; score of Ghost / Ghust: column on row 1
LV_COL:     .byte 7,20                         ; their lives on row 1
PCOL:       .byte 15,7                         ; Ghost white, Ghust cyan
START_X:    .byte 32,208                       ; where they start a room (on the floor)
PROW:       .byte 7,11,15,19                   ; rows of the platforms
BITS:       .byte 1,2,4,8,16
GHOST_TXT:  .byte "GHOST"
TXT_ROOMH:  .byte "ROOM "
; speed of the levels 0-7: 0.5, 0.75, 1, 1.25, 1.5, 1.75, 2, 2.25 pixels a frame
SPD_L:      .byte $80,$C0,$00,$40,$80,$C0,$00,$40
SPD_H:      .byte $00,$00,$01,$01,$01,$01,$02,$02
; per kind: -, bat, spider, pumpkin, candle, armour, flame, sun, sweet, puff
KCOL:       .byte 0,13,15,9,11,14,9,11,15,15
KPAT:       .byte 0,PT_BAT1,PT_SPI1,PT_PUM1,PT_CAN1,PT_ARM1,PT_FLAME,PT_SUN1,PT_CANDY1,PT_PUFF
; sweets: 3 kinds, the lantern, the bell
SWPAT:      .byte PT_CANDY1,PT_CANDY2,PT_CANDY3,PT_CANDY2,PT_CANDY1
SWCOL:      .byte 9,13,10,11,15
SWEETPTS:   .byte $01,$03,$05                  ; 100, 300, 500 (BCD hundreds)
POPPTS:     .byte $10,$20,$40,$80              ; 1000 2000 4000 8000 in a chain

; title: Ghost, Ghust, the bat, the spider, the pumpkin (sprite Y, X, pattern, colour)
TITLE_NS = 5
TITLE_SY:   .byte 91,91,91,107,123
TITLE_SX:   .byte 184,208,40,40,40
TITLE_SN:   .byte PT_GH1,PT_GHL1,PT_BAT1,PT_SPI1,PT_PUM1
TITLE_SC:   .byte 15,7,13,15,9

; text records: row, column, characters, 0   (end of list: $FF)
TXT_TOP:
  .byte 0,0,"GHOST",0
  .byte 0,14,"HI",0
  .byte $FF
TXT_TOP2:
  .byte 0,27,"GHUST",0,$FF
TXT_BUTTONS:
  .byte 20,6,"BUTTON 1 = 1 PLAYER",0
  .byte 21,6,"BUTTON 2 = 2 PLAYERS",0
  .byte 23,3,"DEVELOPED BY BOOGS & CCAI",0
  .byte $FF
TXT_TITLE:
  .byte 9,4,"SHOOT A CLOUD AT THEM,",0
  .byte 10,4,"THEN POP IT WITH A TOUCH",0
  .byte 12,8,"BAT",0
  .byte 14,8,"SPIDER",0
  .byte 16,8,"PUMPKIN",0
  .byte 18,2,"POP THEM TOGETHER 1000-8000",0
  .byte $FF
TXT_ROOM:
  .byte 9,12,"ROOM ",0,$FF
TXT_CLEAR:
  .byte 9,11,"ROOM CLEAR",0,$FF
TXT_HOME:
  .byte 9,7,"THE VILLA IS FREE",0,$FF
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
;  GRAPHICS, ROOMS AND SOUND TABLES (generated)
; ===============================================================
; GHOST & GHUST: generated by dev/gen_ghost_ghust.js (do not edit by hand)

; sprite patterns (16x16), value = pattern number * 4
PT_GH1 = 0
PT_GH2 = 4
PT_GHL1 = 8
PT_GHL2 = 12
PT_GHD = 16
PT_CLOUD = 20
PT_CLOUDE = 24
PT_LG = 28
PT_LH = 32
PT_LO = 36
PT_LS = 40
PT_LT = 44
PT_BAT1 = 48
PT_BAT2 = 52
PT_SPI1 = 56
PT_SPI2 = 60
PT_PUM1 = 64
PT_PUM2 = 68
PT_CAN1 = 72
PT_CAN2 = 76
PT_CANL1 = 80
PT_CANL2 = 84
PT_ARM1 = 88
PT_ARM2 = 92
PT_ARMH = 96
PT_FLAME = 100
PT_SUN1 = 104
PT_SUN2 = 108
PT_CANDY1 = 112
PT_CANDY2 = 116
PT_CANDY3 = 120
PT_PUFF = 124
SPR_LEN = 1024
SPR_PAGES = 4
SPRITES:
  .byte $07,$1F,$3F,$7C,$7C,$7F,$7F,$7C,$7E,$7F,$7F,$7F,$7F,$77,$43,$00,$E0,$F8,$FC,$CE,$CE,$FE,$FE,$3E,$7E,$FE,$FE,$FE,$FE,$BC,$08,$00
  .byte $07,$1F,$3F,$7C,$7C,$7F,$7F,$7C,$7E,$7F,$7F,$7F,$7F,$3D,$10,$00,$E0,$F8,$FC,$CE,$CE,$FE,$FE,$3E,$7E,$FE,$FE,$FE,$FE,$EE,$C2,$00
  .byte $07,$1F,$3F,$73,$73,$7F,$7F,$7C,$7E,$7F,$7F,$7F,$7F,$3D,$10,$00,$E0,$F8,$FC,$3E,$3E,$FE,$FE,$3E,$7E,$FE,$FE,$FE,$FE,$EE,$C2,$00
  .byte $07,$1F,$3F,$73,$73,$7F,$7F,$7C,$7E,$7F,$7F,$7F,$7F,$77,$43,$00,$E0,$F8,$FC,$3E,$3E,$FE,$FE,$3E,$7E,$FE,$FE,$FE,$FE,$BC,$08,$00
  .byte $00,$07,$1F,$3F,$75,$7B,$75,$7F,$7C,$7B,$7F,$7F,$7F,$36,$44,$00,$00,$E0,$F8,$FC,$AE,$DE,$AE,$FE,$3E,$DE,$FE,$FE,$FE,$6C,$22,$00
  .byte $00,$07,$1F,$38,$60,$60,$C0,$C0,$C0,$C0,$60,$60,$38,$1F,$07,$00,$00,$E0,$F8,$1C,$06,$06,$03,$03,$03,$03,$06,$06,$1C,$F8,$E0,$00
  .byte $00,$07,$1F,$38,$67,$6B,$CF,$CD,$CF,$C7,$62,$60,$38,$1F,$07,$00,$00,$E0,$F8,$1C,$E6,$D6,$F3,$B3,$F3,$E3,$46,$06,$1C,$F8,$E0,$00
  .byte $00,$07,$1F,$38,$61,$62,$C2,$C2,$C2,$C2,$61,$60,$38,$1F,$07,$00,$00,$E0,$F8,$1C,$E6,$06,$03,$03,$63,$23,$E6,$06,$1C,$F8,$E0,$00
  .byte $00,$07,$1F,$38,$62,$62,$C2,$C3,$C2,$C2,$62,$60,$38,$1F,$07,$00,$00,$E0,$F8,$1C,$26,$26,$23,$E3,$23,$23,$26,$06,$1C,$F8,$E0,$00
  .byte $00,$07,$1F,$38,$61,$62,$C2,$C2,$C2,$C2,$61,$60,$38,$1F,$07,$00,$00,$E0,$F8,$1C,$C6,$26,$23,$23,$23,$23,$C6,$06,$1C,$F8,$E0,$00
  .byte $00,$07,$1F,$38,$61,$62,$C2,$C1,$C0,$C2,$61,$60,$38,$1F,$07,$00,$00,$E0,$F8,$1C,$C6,$26,$03,$C3,$23,$23,$C6,$06,$1C,$F8,$E0,$00
  .byte $00,$07,$1F,$38,$63,$60,$C0,$C0,$C0,$C0,$60,$60,$38,$1F,$07,$00,$00,$E0,$F8,$1C,$E6,$86,$83,$83,$83,$83,$86,$06,$1C,$F8,$E0,$00
  .byte $00,$00,$00,$81,$C3,$E7,$FF,$7E,$3D,$19,$01,$00,$00,$00,$00,$00,$00,$00,$00,$81,$C3,$E7,$FF,$7E,$BC,$98,$80,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$03,$07,$1F,$7F,$DF,$8F,$05,$00,$00,$00,$00,$00,$00,$00,$00,$00,$C0,$E0,$F8,$FE,$FB,$F1,$A0,$00,$00,$00,$00
  .byte $01,$01,$01,$09,$17,$2F,$4D,$8F,$9F,$2F,$47,$43,$81,$00,$00,$00,$80,$80,$80,$90,$E8,$F4,$B2,$F1,$F9,$F4,$E2,$C2,$81,$00,$00,$00
  .byte $01,$01,$01,$41,$27,$1F,$2D,$4F,$5F,$8F,$87,$23,$21,$00,$00,$00,$80,$80,$80,$82,$E4,$F0,$B4,$F2,$FA,$F1,$E1,$C4,$84,$00,$00,$00
  .byte $00,$00,$01,$03,$1F,$3F,$77,$63,$7F,$7D,$75,$7B,$3F,$1F,$00,$00,$00,$00,$80,$00,$F8,$FC,$EE,$C6,$FE,$BE,$AE,$DE,$FC,$F8,$00,$00
  .byte $00,$00,$00,$00,$01,$03,$3F,$77,$63,$7F,$75,$7B,$3F,$1F,$00,$00,$00,$00,$00,$00,$80,$00,$FC,$EE,$C6,$FE,$AE,$DE,$FC,$F8,$00,$00
  .byte $01,$03,$03,$01,$07,$06,$07,$07,$1F,$2F,$07,$07,$0F,$1F,$00,$00,$00,$80,$80,$00,$E0,$60,$E0,$E0,$F8,$D0,$E0,$E0,$F0,$F8,$00,$00
  .byte $00,$01,$03,$01,$07,$06,$07,$07,$0F,$0B,$07,$07,$0F,$1F,$00,$00,$80,$C0,$80,$00,$E0,$60,$E0,$E0,$FC,$F4,$E0,$E0,$F0,$F8,$00,$00
  .byte $00,$01,$01,$00,$07,$06,$07,$07,$1F,$0B,$07,$07,$0F,$1F,$00,$00,$80,$C0,$C0,$80,$E0,$60,$E0,$E0,$F8,$F4,$E0,$E0,$F0,$F8,$00,$00
  .byte $01,$03,$01,$00,$07,$06,$07,$07,$3F,$2F,$07,$07,$0F,$1F,$00,$00,$00,$80,$C0,$80,$E0,$60,$E0,$E0,$F0,$D0,$E0,$E0,$F0,$F8,$00,$00
  .byte $07,$0F,$0A,$0F,$3F,$6F,$6F,$6F,$0F,$0E,$0E,$0E,$1E,$00,$00,$00,$E0,$F0,$50,$F0,$FC,$F6,$F6,$F6,$F0,$70,$70,$70,$78,$00,$00,$00
  .byte $07,$0F,$0A,$0F,$3F,$6F,$6F,$6F,$0F,$0E,$07,$0E,$1E,$00,$00,$00,$E0,$F0,$50,$F0,$FC,$F6,$F6,$F6,$F0,$70,$70,$38,$38,$00,$00,$00
  .byte $00,$00,$07,$05,$3F,$6F,$6F,$6F,$0F,$0E,$0E,$0E,$1E,$00,$00,$00,$00,$00,$E0,$A0,$FC,$F6,$F6,$F6,$F0,$70,$70,$70,$78,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$03,$0F,$3F,$7F,$3F,$0F,$03,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$C0,$F0,$F8,$F0,$C0,$00,$00,$00,$00,$00
  .byte $01,$21,$10,$03,$0F,$0F,$DF,$DF,$0F,$0F,$03,$10,$21,$01,$00,$00,$80,$84,$08,$C0,$F0,$F0,$FB,$FB,$F0,$F0,$C0,$08,$84,$80,$00,$00
  .byte $00,$21,$10,$03,$0F,$0F,$00,$00,$0F,$0F,$03,$10,$21,$00,$00,$00,$00,$84,$08,$C0,$F0,$F0,$00,$00,$F0,$F0,$C0,$08,$84,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$83,$CF,$FF,$CF,$83,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$C1,$F3,$FB,$F3,$C1,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$07,$0D,$0B,$0D,$07,$01,$01,$01,$01,$01,$00,$00,$00,$00,$00,$00,$E0,$B0,$D0,$B0,$E0,$80,$80,$80,$80,$80,$00,$00,$00,$00
  .byte $00,$00,$00,$01,$01,$0F,$15,$1F,$1F,$15,$1F,$3F,$00,$00,$00,$00,$00,$00,$00,$00,$00,$F0,$50,$F8,$F8,$54,$F8,$FC,$00,$00,$00,$00
  .byte $00,$00,$10,$08,$45,$20,$07,$CF,$07,$20,$45,$08,$10,$00,$00,$00,$00,$00,$40,$84,$10,$08,$C0,$E6,$C0,$08,$10,$84,$40,$00,$00,$00

; game tiles 96-125: patterns and colours
TILEP:
  .byte $FF,$88,$88,$FF,$C4,$22,$22,$FF,$FF,$FF,$AA,$55,$FF,$FF,$00,$00,$FF,$FF,$AA,$55,$FF,$88,$88,$FF,$FF,$99,$99,$FF,$99,$99,$99,$FF
  .byte $FF,$92,$92,$FF,$92,$92,$92,$FF,$FF,$FF,$AA,$55,$FF,$FF,$00,$00,$FF,$FF,$AA,$55,$FF,$88,$88,$FF,$FF,$99,$99,$FF,$99,$99,$99,$FF
  .byte $B5,$B5,$B5,$B5,$B5,$B5,$B5,$FF,$FF,$FF,$AA,$55,$FF,$FF,$00,$00,$FF,$FF,$AA,$55,$FF,$88,$88,$FF,$FF,$99,$99,$FF,$99,$99,$99,$FF
  .byte $FF,$81,$BD,$A5,$A5,$BD,$81,$FF,$FF,$FF,$AA,$55,$FF,$FF,$00,$00,$FF,$FF,$AA,$55,$FF,$88,$88,$FF,$FF,$99,$99,$FF,$99,$99,$99,$FF
  .byte $FF,$81,$A5,$99,$99,$A5,$81,$FF,$FF,$FF,$AA,$55,$FF,$FF,$00,$00,$FF,$FF,$AA,$55,$FF,$88,$88,$FF,$FF,$99,$99,$FF,$99,$99,$99,$FF
  .byte $FF,$88,$88,$FF,$C4,$22,$22,$FF,$FF,$FF,$AA,$55,$FF,$FF,$00,$00,$FF,$FF,$AA,$55,$FF,$88,$88,$FF,$FF,$99,$99,$FF,$99,$99,$99,$FF
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $3C,$7E,$DB,$FF,$FF,$FF,$A5,$00,$00,$00,$00,$18,$18,$00,$00,$00
TILEC:
  .byte $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$F1,$E1,$E1,$E1,$E1,$E1,$11,$11,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$41,$41,$E1,$41,$41,$41,$E1
  .byte $B6,$B6,$B6,$B6,$B6,$B6,$B6,$B6,$F1,$A1,$A1,$A1,$A1,$A1,$11,$11,$B6,$B6,$B6,$B6,$B6,$B6,$B6,$B6,$B1,$41,$41,$B1,$41,$41,$41,$B1
  .byte $AC,$AC,$AC,$AC,$AC,$AC,$AC,$AC,$B1,$61,$61,$61,$61,$61,$11,$11,$AC,$AC,$AC,$AC,$AC,$AC,$AC,$AC,$A1,$41,$41,$A1,$41,$41,$41,$A1
  .byte $D5,$D5,$D5,$D5,$D5,$D5,$D5,$D5,$F1,$D1,$D1,$D1,$D1,$D1,$11,$11,$D5,$D5,$D5,$D5,$D5,$D5,$D5,$D5,$D1,$41,$41,$D1,$41,$41,$41,$D1
  .byte $A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$B1,$A1,$A1,$A1,$A1,$A1,$11,$11,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$41,$41,$A1,$41,$41,$41,$A1
  .byte $74,$74,$74,$74,$74,$74,$74,$74,$F1,$71,$71,$71,$71,$71,$11,$11,$74,$74,$74,$74,$74,$74,$74,$74,$71,$41,$41,$71,$41,$41,$41,$71
  .byte $11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
TILE_FIRST = 96
TILE_N = 30

; the rooms: 4 platform masks (rows 7, 11, 15, 19; bit b = columns 2+2b and its mirror),
; where the clouds gather, the enemies (kind, platform row index, x), 0 = end
RM0:
  .byte $6C,$7E,$40,$1E,$40,$02,$00,$90,$01,$00,$70,$02,$01,$20,$00
RM1:
  .byte $38,$7C,$7F,$46,$78,$02,$01,$70,$01,$01,$C0,$02,$01,$90,$01,$03,$20,$00
RM2:
  .byte $08,$4E,$43,$60,$B0,$02,$02,$20,$01,$01,$70,$02,$03,$90,$00
RM3:
  .byte $07,$60,$40,$70,$40,$02,$03,$A0,$01,$03,$80,$02,$03,$70,$01,$00,$C0,$00
RM4:
  .byte $70,$60,$38,$18,$78,$02,$02,$90,$01,$03,$A0,$02,$00,$70,$00
RM5:
  .byte $60,$60,$60,$67,$B0,$02,$02,$70,$01,$02,$90,$04,$02,$60,$02,$01,$90,$00
RM6:
  .byte $01,$6F,$37,$08,$40,$02,$00,$E0,$01,$03,$40,$04,$02,$30,$02,$00,$E0,$00
RM7:
  .byte $78,$78,$70,$41,$78,$02,$02,$60,$01,$03,$10,$04,$02,$A0,$02,$00,$B0,$01,$03,$10,$00
RM8:
  .byte $20,$08,$3C,$38,$B0,$02,$02,$C0,$01,$01,$B0,$04,$02,$C0,$02,$02,$A0,$00
RM9:
  .byte $0E,$6C,$0C,$0F,$40,$02,$01,$90,$01,$03,$30,$04,$02,$40,$02,$02,$B0,$01,$01,$90,$00
RM10:
  .byte $7C,$06,$43,$06,$78,$01,$02,$80,$04,$03,$20,$03,$02,$D0,$01,$01,$D0,$00
RM11:
  .byte $70,$05,$3C,$78,$B0,$01,$00,$80,$04,$02,$50,$03,$01,$10,$01,$02,$B0,$04,$02,$B0,$00
RM12:
  .byte $40,$7E,$1C,$58,$40,$01,$03,$B0,$04,$01,$90,$03,$00,$70,$01,$01,$20,$04,$00,$70,$00
RM13:
  .byte $7E,$78,$4E,$48,$78,$01,$01,$50,$04,$00,$D0,$03,$01,$60,$01,$01,$60,$04,$03,$70,$03,$03,$B0,$00
RM14:
  .byte $60,$1E,$78,$71,$B0,$01,$01,$30,$04,$00,$90,$03,$00,$90,$01,$02,$80,$04,$03,$80,$00
RM15:
  .byte $7A,$78,$20,$7C,$40,$03,$03,$B0,$05,$01,$70,$02,$01,$40,$03,$01,$70,$05,$01,$A0,$02,$01,$60,$00
RM16:
  .byte $05,$70,$3C,$78,$78,$03,$02,$40,$05,$02,$50,$02,$01,$50,$03,$01,$A0,$05,$01,$80,$00
RM17:
  .byte $40,$3C,$10,$06,$B0,$03,$01,$90,$05,$02,$A0,$02,$00,$80,$03,$01,$30,$05,$00,$80,$02,$02,$50,$00
RM18:
  .byte $72,$67,$78,$02,$40,$03,$01,$80,$05,$03,$D0,$02,$02,$60,$03,$03,$D0,$05,$02,$80,$02,$02,$80,$00
RM19:
  .byte $70,$48,$3E,$0F,$78,$03,$00,$60,$05,$01,$40,$02,$02,$C0,$03,$03,$E0,$05,$00,$50,$02,$00,$70,$00
RM20:
  .byte $7D,$0F,$0C,$78,$B0,$01,$00,$C0,$03,$01,$40,$05,$01,$C0,$04,$03,$90,$01,$02,$30,$03,$02,$30,$00
RM21:
  .byte $50,$70,$3C,$5F,$40,$01,$02,$A0,$03,$00,$A0,$05,$03,$10,$04,$03,$40,$01,$03,$C0,$03,$00,$80,$00
RM22:
  .byte $34,$73,$04,$47,$78,$01,$03,$80,$03,$00,$A0,$05,$00,$50,$04,$02,$30,$01,$02,$30,$03,$02,$C0,$00
RM23:
  .byte $7C,$1E,$18,$4C,$B0,$01,$03,$40,$03,$03,$70,$05,$03,$B0,$04,$03,$80,$01,$01,$40,$03,$03,$C0,$00
RM24:
  .byte $30,$70,$0C,$1E,$40,$01,$00,$90,$03,$00,$A0,$05,$02,$C0,$04,$02,$C0,$01,$03,$B0,$03,$02,$B0,$00
RM25:
  .byte $76,$5F,$1E,$40,$78,$05,$02,$D0,$04,$01,$C0,$03,$01,$20,$01,$00,$80,$02,$03,$80,$05,$02,$B0,$00
RM26:
  .byte $5F,$6C,$0F,$60,$B0,$05,$00,$A0,$04,$00,$70,$03,$03,$80,$01,$01,$60,$02,$01,$60,$05,$03,$60,$00
RM27:
  .byte $1C,$7C,$18,$7B,$40,$05,$00,$B0,$04,$03,$70,$03,$00,$A0,$01,$00,$40,$02,$03,$A0,$05,$00,$50,$00
RM28:
  .byte $7C,$3C,$70,$0C,$78,$05,$03,$40,$04,$00,$80,$03,$02,$A0,$01,$00,$C0,$02,$00,$80,$05,$00,$90,$00
RM29:
  .byte $63,$06,$68,$7C,$B0,$05,$03,$90,$04,$01,$D0,$03,$03,$A0,$01,$00,$90,$02,$00,$D0,$05,$03,$60,$00
RM_LO:
  .byte <RM0,<RM1,<RM2,<RM3,<RM4,<RM5,<RM6,<RM7,<RM8,<RM9,<RM10,<RM11,<RM12,<RM13,<RM14,<RM15,<RM16,<RM17,<RM18,<RM19,<RM20,<RM21,<RM22,<RM23,<RM24,<RM25,<RM26,<RM27,<RM28,<RM29
RM_HI:
  .byte >RM0,>RM1,>RM2,>RM3,>RM4,>RM5,>RM6,>RM7,>RM8,>RM9,>RM10,>RM11,>RM12,>RM13,>RM14,>RM15,>RM16,>RM17,>RM18,>RM19,>RM20,>RM21,>RM22,>RM23,>RM24,>RM25,>RM26,>RM27,>RM28,>RM29
; names of the floors (12 characters)
FLOOR_TXT:
  .byte "THE CELLAR  "
  .byte "THE KITCHEN "
  .byte "THE LIBRARY "
  .byte "THE HALL    "
  .byte "THE ATTIC   "
  .byte "THE TOWER   "

; big letters of the title
BIG_TOP:
  .byte $00,$07,$07,$18,$18,$18,$18,$18,$00,$F8,$F8,$00,$00,$00,$00,$00,$00,$18,$18,$18,$18,$18,$18,$1F,$00,$18,$18,$18,$18,$18,$18,$F8
  .byte $00,$07,$07,$18,$18,$18,$18,$18,$00,$E0,$E0,$18,$18,$18,$18,$18,$00,$07,$07,$18,$18,$18,$18,$07,$00,$E0,$E0,$18,$18,$00,$00,$E0
  .byte $00,$1F,$1F,$01,$01,$01,$01,$01,$00,$F8,$F8,$80,$80,$80,$80,$80,$00,$06,$06,$19,$19,$19,$19,$06,$00,$00,$00,$80,$80,$80,$80,$00
  .byte $00,$18,$18,$18,$18,$18,$18,$18,$00,$18,$18,$18,$18,$18,$18,$18
BIG_BOT:
  .byte $18,$18,$18,$18,$18,$07,$07,$00,$00,$78,$78,$18,$18,$F8,$F8,$00,$1F,$18,$18,$18,$18,$18,$18,$00,$F8,$18,$18,$18,$18,$18,$18,$00
  .byte $18,$18,$18,$18,$18,$07,$07,$00,$18,$18,$18,$18,$18,$E0,$E0,$00,$07,$00,$00,$18,$18,$07,$07,$00,$E0,$18,$18,$18,$18,$E0,$E0,$00
  .byte $01,$01,$01,$01,$01,$01,$01,$00,$80,$80,$80,$80,$80,$80,$80,$00,$06,$19,$19,$18,$18,$07,$07,$00,$00,$98,$98,$60,$60,$98,$98,$00
  .byte $18,$18,$18,$18,$18,$07,$07,$00,$18,$18,$18,$18,$18,$E0,$E0,$00
TXT_BIG:
  .byte 3,3,160,161,162,163,164,165,166,167,168,169,32,32,170,171,32,32,160,161,162,163,172,173,166,167,168,169,0
  .byte 4,3,192,193,194,195,196,197,198,199,200,201,32,32,202,203,32,32,192,193,194,195,204,205,198,199,200,201,0
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
  .byte $29,$08,$2E,$08,$31,$08,$30,$10,$2E,$08,$2D,$08,$30,$08,$35,$08,$33,$10,$31,$08,$30,$08,$31,$08,$2E,$08,$2A,$10,$29,$08,$27,$08
  .byte $29,$08,$2D,$08,$30,$18,$29,$08,$2E,$08,$31,$08,$35,$10,$33,$08,$31,$08,$33,$08,$30,$08,$2C,$10,$2A,$08,$29,$08,$2A,$08,$27,$08
  .byte $24,$08,$25,$08,$29,$08,$2E,$20,$FF
SG0_1:
  .byte $25,$18,$29,$18,$22,$18,$27,$18,$25,$18,$24,$18,$25,$18,$25,$18,$24,$18,$22,$18,$21,$18,$22,$20,$FF
SG0_2:
  .byte $0A,$08,$11,$08,$11,$08,$09,$08,$11,$08,$11,$08,$0A,$08,$11,$08,$11,$08,$0F,$08,$16,$08,$16,$08,$11,$08,$15,$08,$15,$08,$05,$08
  .byte $0C,$08,$0C,$08,$0A,$08,$11,$08,$11,$08,$0A,$08,$11,$08,$11,$08,$08,$08,$0F,$08,$0F,$08,$0F,$08,$16,$08,$16,$08,$11,$08,$18,$08
  .byte $18,$08,$0A,$08,$11,$08,$16,$10,$FF
SG0_3:
  .byte $01,$18,$01,$18,$01,$18,$01,$18,$01,$18,$01,$18,$01,$18,$01,$18,$01,$18,$01,$18,$01,$18,$01,$18,$04,$20,$FF
SG1_0:
  .byte $2E,$06,$31,$06,$35,$06,$3A,$0C,$39,$06,$35,$06,$36,$06,$33,$06,$30,$06,$35,$12,$FF
SG1_1:
  .byte $25,$18,$22,$18,$21,$1E,$FF
SG1_2:
  .byte $0A,$0C,$11,$0C,$0F,$0C,$05,$1E,$FF
SG1_3:
  .byte $01,$0C,$03,$0C,$02,$0C,$03,$0C,$04,$1E,$FF
SG2_0:
  .byte $35,$06,$31,$06,$2E,$06,$31,$06,$33,$06,$30,$06,$2D,$06,$30,$06,$31,$06,$35,$06,$3A,$1E,$FF
SG2_1:
  .byte $22,$18,$21,$18,$22,$24,$FF
SG2_2:
  .byte $0A,$0C,$11,$0C,$05,$0C,$11,$0C,$0A,$24,$FF
SG2_3:
  .byte $02,$06,$03,$06,$03,$06,$03,$06,$02,$06,$03,$06,$03,$06,$03,$06,$02,$06,$03,$06,$04,$1E,$FF
SG3_0:
  .byte $22,$08,$25,$08,$29,$08,$2E,$18,$2C,$08,$2A,$08,$29,$08,$27,$18,$2A,$08,$29,$08,$27,$08,$25,$10,$24,$10,$22,$30,$FF
SG3_1:
  .byte $1D,$18,$1D,$18,$1B,$18,$1B,$18,$19,$18,$18,$18,$19,$30,$FF
SG3_2:
  .byte $0A,$18,$0D,$18,$0F,$18,$12,$18,$11,$18,$05,$18,$0A,$30,$FF
SG3_3:
  .byte $01,$18,$02,$18,$01,$18,$02,$18,$01,$18,$02,$18,$04,$30,$FF

; one-shot tone effects: period and volume for every frame
WH_TL:
  .byte $00,$45,$3B,$33,$2D,$29,$25,$9C,$79,$63,$53,$48,$40,$39,$2F,$2F,$2F,$3C,$3C,$3C,$3C,$3C,$1E,$1E,$27,$2E,$39,$4A,$68,$28,$28,$28
  .byte $1B,$1B,$1B,$1B,$1B,$F0,$F0,$D0,$D0,$F0,$F0,$D0,$D0,$F0,$F0,$D0,$D0,$F0,$F0,$D0,$D0,$47,$47,$47,$47,$47,$47,$47,$47,$38,$38,$38
  .byte $38,$38,$38,$38,$38,$2F,$2F,$2F,$2F,$2F,$2F,$2F,$2F,$24,$24,$24,$24,$24,$24,$24,$24,$34,$36,$37,$39,$3B,$3D,$40,$42,$45,$47,$4B
  .byte $4E,$52,$56,$5A,$5F,$65,$6B,$72,$7A,$83,$8E,$9B,$AA,$BD,$D4,$F2,$19,$50,$A1,$3C,$3C,$3C,$3C,$00,$00,$2F,$2F,$2F,$2F,$00,$00,$28
  .byte $28,$28,$28,$00,$00,$1E,$1E,$1E,$1E,$1E,$1E,$24,$24,$24,$1C,$1C,$1C,$18,$18,$18,$18,$18,$18,$8E,$8E,$8E,$8E,$8E,$8E,$8E,$8E,$97
  .byte $97,$97,$97,$97,$97,$97,$97,$9F,$9F,$9F,$9F,$9F,$9F,$9F,$9F,$BD,$BD,$BD,$BD,$BD,$BD,$BD,$BD,$BD,$BD,$BD,$BD,$BD,$BD,$BD,$BD,$7D
  .byte $88,$95,$A4,$B8,$D0,$18,$20,$20,$5F,$5F,$5F,$5F,$47,$47,$47,$47,$3C,$3C,$3C,$2F,$2F,$2F,$2F,$2F,$2F,$2F,$2F
WH_TH:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$01,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
WH_VOL:
  .byte $00,$0A,$09,$08,$07,$06,$05,$0A,$09,$08,$08,$07,$06,$05,$0B,$0A,$09,$0B,$0A,$08,$07,$05,$0C,$09,$09,$08,$06,$05,$03,$0C,$0B,$0A
  .byte $0C,$0A,$09,$07,$05,$0C,$0C,$0C,$0C,$0B,$0B,$0B,$0B,$0A,$0A,$0A,$0A,$09,$09,$09,$09,$0C,$0B,$0A,$09,$09,$08,$07,$06,$0C,$0B,$0A
  .byte $09,$09,$08,$07,$06,$0C,$0B,$0A,$09,$09,$08,$07,$06,$0C,$0B,$0A,$09,$09,$08,$07,$06,$0D,$0D,$0C,$0C,$0C,$0B,$0B,$0B,$0A,$0A,$0A
  .byte $09,$09,$09,$08,$08,$07,$07,$07,$06,$06,$06,$05,$05,$05,$04,$04,$04,$03,$03,$0D,$0C,$0A,$09,$00,$00,$0D,$0C,$0A,$09,$00,$00,$0D
  .byte $0C,$0A,$09,$00,$00,$0D,$0B,$09,$08,$06,$04,$0C,$0B,$09,$0C,$0B,$09,$0C,$0A,$09,$07,$06,$04,$0C,$0B,$0A,$09,$09,$08,$07,$06,$0C
  .byte $0B,$0A,$09,$09,$08,$07,$06,$0C,$0B,$0A,$09,$09,$08,$07,$06,$0C,$0C,$0B,$0B,$0A,$0A,$0A,$09,$09,$08,$08,$08,$07,$07,$06,$06,$08
  .byte $07,$06,$05,$04,$03,$0A,$08,$05,$0C,$0B,$0A,$09,$0C,$0B,$0A,$09,$0C,$0B,$09,$0D,$0C,$0A,$09,$07,$06,$04,$03
WH_START:
  .byte $00,$01,$07,$0E,$16,$1D,$25,$35,$55,$73,$8B,$97,$BF,$C5,$C8
WH_LEN:
  .byte $00,$06,$07,$08,$07,$08,$10,$20,$1E,$18,$0C,$28,$06,$03,$13
W_SHOOT = 1
W_JUMP = 2
W_CATCH = 3
W_POP = 4
W_CANDY = 5
W_ANGRY = 6
W_DAWN = 7
W_DIE = 8
W_EXTRA = 9
W_LETTER = 10
W_OVER = 11
W_FLAME = 12
W_KEY = 13
W_SIGN = 14

; noise effects: noise volume / period, low tone volume / period for every frame
EX_NV:
  .byte $00,$0C,$0A,$08,$06,$04,$02,$00,$00,$0E,$0E,$0D,$0D,$0C,$0C,$0B,$0B,$0A,$0A,$09,$09,$08,$08,$07,$07,$06,$06,$05,$05,$04,$04,$03
  .byte $03
EX_NP:
  .byte $00,$02,$03,$04,$05,$06,$07,$08,$09,$06,$06,$06,$06,$07,$07,$07,$07,$08,$08,$08,$08,$09,$09,$09,$09,$0A,$0A,$0A,$0A,$0B,$0B,$0B
  .byte $0B
EX_VC:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$0C,$0C,$0B,$0B,$0A,$0A,$09,$09,$08,$08,$07,$07,$06,$06,$05,$05,$04,$04,$03,$03,$02,$02,$01
  .byte $01
EX_TL:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$0D,$71,$0D,$71,$0D,$71,$0D,$71,$0D,$71,$0D,$71,$0D,$71,$0D,$71,$0D,$71,$0D,$71,$0D,$71,$0D
  .byte $71
EX_TH:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$03,$02,$03,$02,$03,$02,$03,$02,$03,$02,$03,$02,$03,$02,$03,$02,$03,$02,$03,$02,$03,$02,$03
  .byte $02
EX_START:
  .byte $00,$01,$09
EX_LEN:
  .byte $00,$08,$18
S_POP = 1
S_BIG = 2

GFX_LOAD:
  .byte 1, $00,$41, <512,>512, <FONT,>FONT
  .byte 2, $00,$61, <512,>512, $F1,0
  .byte 1, $00,$45, <112,>112, <BIG_TOP,>BIG_TOP
  .byte 1, $00,$46, <112,>112, <BIG_BOT,>BIG_BOT
  .byte 2, $00,$65, <112,>112, $71,0
  .byte 2, $00,$66, <112,>112, $F1,0
  .byte 1, $00,$43, <240,>240, <TILEP,>TILEP
  .byte 1, $00,$63, <240,>240, <TILEC,>TILEC
  .byte 2, $00,$60, <8,>8, $11,0
  .byte 1, $00,$49, <512,>512, <FONT,>FONT
  .byte 2, $00,$69, <512,>512, $F1,0
  .byte 1, $00,$4D, <112,>112, <BIG_TOP,>BIG_TOP
  .byte 1, $00,$4E, <112,>112, <BIG_BOT,>BIG_BOT
  .byte 2, $00,$6D, <112,>112, $71,0
  .byte 2, $00,$6E, <112,>112, $F1,0
  .byte 1, $00,$4B, <240,>240, <TILEP,>TILEP
  .byte 1, $00,$6B, <240,>240, <TILEC,>TILEC
  .byte 2, $00,$68, <8,>8, $11,0
  .byte 1, $00,$51, <512,>512, <FONT,>FONT
  .byte 2, $00,$71, <512,>512, $F1,0
  .byte 1, $00,$55, <112,>112, <BIG_TOP,>BIG_TOP
  .byte 1, $00,$56, <112,>112, <BIG_BOT,>BIG_BOT
  .byte 2, $00,$75, <112,>112, $71,0
  .byte 2, $00,$76, <112,>112, $F1,0
  .byte 1, $00,$53, <240,>240, <TILEP,>TILEP
  .byte 1, $00,$73, <240,>240, <TILEC,>TILEC
  .byte 2, $00,$70, <8,>8, $11,0
  .byte 2, $00,$78, <768,>768, $20,0
  .byte 0
