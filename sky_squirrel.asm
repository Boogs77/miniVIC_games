;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;                                                              ;
;   SKY SQUIRREL  -  an original jump and glide platform game  ;
;   65C02 assembly, TMS9918A Graphics II (tiles + sprites)     ;
;                                                              ;
;   - Pip, a flying squirrel, gathers the acorns a storm       ;
;     scattered: 24 acorns on every stage, 15 stages in five   ;
;     places (oak wood, waterfall, old mill, city roofs, snow  ;
;     peaks), then the world again, faster                     ;
;   - button 1 = jump: held longer, higher (UP helps too);     ;
;     press it again in the air and Pip glides down slowly     ;
;     while it is held; DOWN = drop fast                       ;
;   - one acorn at a time shines: take it and the next one     ;
;     shines (the chain); a shining acorn is worth 200, the    ;
;     others 100; at the end of the stage 1000 for every       ;
;     acorn of the chain, 50000 for a chain of all 24          ;
;   - owls, wasps, hedgehogs, crows and pine cones come in     ;
;     from the top; hedgehogs that reach the ground become     ;
;     owls. The gold acorn turns them into nuts for a while:   ;
;     200, 400, 800, 1600, 2000                                ;
;   - leaves float down now and then: X = the points count     ;
;     one time more (up to 5), 1UP = a life more              ;
;   - 3 lives, one more at 30000 and every 60000; 1 or 2       ;
;     players taking turns                                     ;
;   - records: the 8 best scores, signed with 3 initials, kept ;
;     on the SD with the BIOS KEYB/SD (zone 33 of the save     ;
;     area, lib_records.asm)                                   ;
;   - SOUND (2 x AY-3-8910, played from the NMI at 60 Hz):     ;
;     tunes at the title, at every stage and at its end;       ;
;     jumps, glides, acorns, nuts, leaves                      ;
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
SCRN        = $40      ; ---- block of the player, saved: stage 0-14
LOOPN       = $41      ;      round of the world
NEXTX       = $42      ;      next extra life (BCD, ten thousands)
FRESH       = $43      ;      1 = a new stage (the tune)
TAKEN       = $44      ;      3 bytes: the acorns already taken (bit = acorn)
LITI        = $47      ;      place in the shining order of the shining acorn (24 = none)
CHAINN      = $48      ;      shining acorns taken in this stage
MULT        = $49      ;      the points count MULT times (1-5)
PBLOCK      = 10
GSTATE      = $50      ; 0 playing, 1 Pip was hit, 3 every acorn taken
GT          = $51      ; timer of GSTATE
HUDD        = $52      ; to draw again: 1 score, 2 the status row
FIRSTT      = $53      ; 1 = first turn of the game
NLEFT       = $54      ; acorns left on the stage
BACKN       = $55      ; the place 0-4 (stage / 3)
SPDBASE     = $56      ; speed level the foes start with
SPAWNT      = $57      ; frames to the next foe
SPAWNI      = $58      ;   (frames between two foes on this stage)
NENEM       = $59      ; foes on the stage (coming in too)
MAXEN       = $5A      ; foes at most on this stage
POWERT      = $5B      ; the gold acorn: 2-frame units left (0 = off)
NUTN        = $5C      ; nuts taken in this power
GOLDC       = $5D      ; acorns taken since the last gold acorn
LEAFT       = $5E      ; seconds to the next leaf
SECF        = $5F      ; frames of the second
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
GLOWS       = $72      ; the shining acorn: 0 / 1 (the flash)
SPAWNN      = $73      ; foes come in so far (kind and door)
GOLDON      = $74      ; 1 = a gold acorn is on the stage
LOSTN       = $75      ; lives lost (tests)
DEATH       = $76      ; what took the last life (kind, tests)
JOYC        = $77      ; both joysticks drive the player playing
JOYP        = $78      ;   (the frame before)
ACN         = $79      ; acorns taken (tests)
HITR        = $7A      ; a tile: row
HITC        = $7B      ;         column
OI          = $7C      ; object being handled
PSX         = $7D      ; where Pip starts this stage
PSY         = $7E
NUTS        = $7F      ; nuts taken (tests)
OWLMAX      = $8C      ; owls at most on this stage
P_JOY       = $80      ; 2 bytes (joystick, 1 = pressed)
PTS_L       = $82      ; points to add (BCD)
PTS_M       = $83
PTS_H       = $84
SATB        = $85      ; bytes of the SAT to copy
HOFF        = $86      ; name table of NT_XY and CLEAR_NT (always 0 here)
RR          = $87      ; first object in the SAT (turns)
MLOOP       = $88      ; times left of the multiplier
LYPTR       = $8A      ; 2 bytes: the layout of the stage
; ---- Pip
PX          = $90      ; left x
PXF         = $91
PY          = $92      ; top y
PYF         = $93
PVYL        = $94      ; vertical speed 8.8 (signed)
PVYH        = $95
PST         = $96      ; 1 on a platform, 2 in the air, 3 hit (falls away)
PDIR        = $97      ; 0 right, 1 left
PTH         = $98      ; frames of thrust left in the jump
PGL         = $99      ; 1 = gliding
PMV         = $9A      ; 1 = running (the picture)
PINV        = $9B      ; frames he cannot be hit (blinks)

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

; ---------------- foes and things: 10 slots ----------------
NOB        = 10
O_K        = $0200       ; kind (K_*, 0 = free)
O_X        = $020A
O_XF       = $0214
O_Y        = $021E
O_YF       = $0228
O_VXL      = $0232       ; speed 8.8 (signed)
O_VXH      = $023C
O_VYL      = $0246
O_VYH      = $0250
O_S        = $025A       ; walkers: 0 on a platform, 1 in the air; leaf: 1 on the ground
O_T        = $0264       ; timer
O_LV       = $026E       ; speed level 0-7
O_H        = $0278       ; coming in: the kind it will be; leaf: 0 X, 1 1UP
O_D        = $0282       ; bit 0: left, bit 1: up

K_OWL      = 1           ; flies after Pip
K_WASP     = 2           ; flies across, wobbling
K_HOG      = 3           ; walks on the platforms, an owl on the ground
K_CROW     = 4           ; flies on the slant
K_CONE     = 5           ; hops
K_SPAWN    = 6           ; a foe coming in (a spark)
K_GOLD     = 7           ; the gold acorn
K_LEAF     = 8           ; a leaf with X or 1UP
K_PUFF     = 9           ; a nut taken

; ---------------- the acorns of the stage ----------------
AC_C       = $0300       ; 24 x: column of the top left tile
AC_R       = $0318       ;       its row
CHAIN      = $0330       ; the shining order (acorn numbers)
AC_X       = $0348       ; the acorn in pixels (left, top)
AC_Y       = $0360
AC_T       = $0378       ; 1 = taken

; ---------------- other RAM ----------------
SAT_BUFFER = $0600       ; 32 sprites x 4 + end of list
PSAVE      = $0690       ; 2 x 16: block of every player
MAP        = $0800       ; the name table (rows 0-23), for the collisions
BACK       = $0B00       ; the backdrop and the platforms, without the acorns

; ---------------- parameters ----------------
BTN_MASK    = %00110000
T_ACORN     = 96         ; 96-99 an acorn, 100-103 the shining one, 106-109 its flash
T_LIT       = 100
T_FLASH     = 106
T_LIFE      = 104
T_MULT      = 105
T_WALL      = 128
T_FLOOR     = 129        ; 129-132 can be stood on (floor, platform ends and middle)
T_PLATL     = 130
T_PLATM     = 131
T_PLATR     = 132
X_MIN       = 8          ; the field (left x, top y of a 16 x 16 sprite)
X_MAX       = 232
Y_MIN       = 24
FLOOR_Y     = 168        ; top y of who stands on the floor (row 23)
JUMP_H      = $FD        ; thrust: -2.5 pixels a frame
JUMP_L      = $80
THRUST      = 34         ; frames of thrust at most
THRUST_MIN  = 5          ; a tap
GRAV        = $26        ; gravity: 0.15 pixels a frame each frame
FALL_MAX    = $02        ; falling: 2.5 pixels a frame at most
FALL_MAXL   = $80
GLIDE_MAX   = $00        ; gliding: 0.5
GLIDE_MAXL  = $80
DIVE_MAX    = $03        ; DOWN held: 3.5
DIVE_MAXL   = $80
GOLD_N      = 9          ; acorns to take for a gold acorn
POWER_T     = 180        ; the gold acorn lasts 6 s (2-frame units)
LEAF_S      = 18         ; seconds between two leaves
OWL_AIM     = 48         ; frames an owl swoops before it looks for Pip again

; ---------------- records on the SD (lib_records.asm) ----------------
REC_ZONE    = 33         ; fixed zone of the game in the save area
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
;  TITLE: the name, the acorns, what they are worth
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

; one frame of the title: Pip glides up and down, the gold acorn sparkles;
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
  LDA SATB                     ; the sprites are there: they move
  CMP #2
  BCC .tf_e
  LDA FRAME_CNT
  LSR A
  LSR A
  LSR A
  LSR A
  AND #7
  TAX
  LDA BOB_T,X
  CLC
  ADC TITLE_SY
  STA SAT_BUFFER
  STA SAT_BUFFER+4
  LDA FRAME_CNT
  AND #8
  BEQ .tf_g
  LDA #PT_GOLD2-PT_GOLD1
.tf_g:
  CLC
  ADC #PT_GOLD1
  STA SAT_BUFFER+4*4+2
.tf_e:
  JMP VDP_INT_ON


; ===============================================================
;  NEW GAME: stage 1, 3 lives for every player
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
  STZ ACN
  STZ NUTS
  LDA NPL
  STA CURP
.ng_w:
  DEC CURP                     ; player NPL-1 ... 0
  LDX CURP
  LDA #3
  STA LIVES,X
  STZ SCRN
  STZ LOOPN
  JSR NEW_STAGE_P
  LDA #$03                     ; first extra life at 30000
  STA NEXTX
  JSR SAVE_PLAYER
  LDA CURP
  BNE .ng_w
  LDA #$01
  STA FIRSTT
  ; fall into TURN_START with CURP = 0

; ===============================================================
;  TURN OF A PLAYER, then his stage
; ===============================================================
TURN_START:
  LDX CURP
  JSR LOAD_PLAYER

STAGE_START:
  LDX #$FF
  TXS
  JSR HIDE_SPRITES
  JSR VDP_INT_OFF
  LDA #$82                     ; display off while the stage is drawn
  STA VREG
  LDA #(VDP_REGISTER_BITS | 1)
  STA VREG
  JSR DRAW_STAGE
  JSR STAGE_INIT
  JSR DRAW_HUD
  JSR MSG_STAGE
  JSR BUILD_SAT
  JSR VDP_INT_ON               ; (display on)
  LDA FIRSTT                   ; the tune: first turn or a new stage
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
  JSR PIP
  LDA GSTATE
  BNE .gl_ns
  JSR ACORNS
  JSR OBJECTS
  JSR TOUCHES
  JSR CLOCK
.gl_ns:
  JSR GLOW
  JSR UPDATE_HUD
  JSR BUILD_SAT
WEND:
  JSR VDP_INT_ON
  LDA JOYC
  STA JOYP
  LDA GSTATE
  BEQ GAME_LOOP
  DEC GT
  BNE GAME_LOOP
  LDA GSTATE
  CMP #3
  BEQ .gl_win
  JMP LOSE_LIFE
.gl_win:
  JMP STAGE_CLEAR


; ===============================================================
;  EVERY ACORN TAKEN: the chain bonus, the next stage
; ===============================================================
STAGE_CLEAR:
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
  LDA CHAINN
  JSR PUT_NUM
  JSR VDP_INT_ON
  LDA #30
  JSR WAIT_FRAMES
  LDA CHAINN                   ; 1000 for every acorn of the chain
  STA T5
.sc_b:
  LDA T5
  BEQ .sc_p
  LDA #5
  JSR WAIT_FRAMES
  JSR VDP_INT_OFF
  DEC T5
  LDA #$00
  LDY #$10
  JSR ADD_PTS
  JSR UPDATE_HUD
  JSR VDP_INT_ON
  LDA #W_TICK
  LDX #2
  JSR SFX_WHISTLE
  BRA .sc_b
.sc_p:
  LDA CHAINN                   ; all 24: 50000 in all
  CMP #24
  BNE .sc_t
  JSR VDP_INT_OFF
  LDA #<TXT_PERFECT
  STA TP
  LDA #>TXT_PERFECT
  STA TP+1
  JSR PRINT
  LDA #$00
  STA PTS_L
  LDA #$60
  STA PTS_M
  LDA #$02
  STA PTS_H
  JSR ADD_SCORE
  JSR UPDATE_HUD
  JSR VDP_INT_ON
  LDA #W_EXTRA
  LDX #2
  JSR SFX_WHISTLE
.sc_t:
  LDA #1
  JSR WAIT_FRAMES
  LDA SND_BUSY
  BNE .sc_t
  LDA #60
  JSR WAIT_FRAMES
  INC SCRN                     ; the next stage; after the peaks, the world again
  LDA SCRN
  CMP #15
  BCC .sc_n
  STZ SCRN
  JSR WORLD_DONE
.sc_n:
  JSR NEW_STAGE_P
  JSR SAVE_PLAYER
  JMP STAGE_START

; the fifteen stages are done: the tune, the world again faster
WORLD_DONE:
  JSR VDP_INT_OFF
  LDA #<TXT_WORLD
  STA TP
  LDA #>TXT_WORLD
  STA TP+1
  JSR PRINT
  JSR VDP_INT_ON
  LDA #3
  STA SONG
  LDA #CMD_START
  STA SND_CMD
  LDA #20
  JSR WAIT_FRAMES
.wd_t:
  LDA #1
  JSR WAIT_FRAMES
  LDA SND_BUSY
  BNE .wd_t
  LDA #60
  JSR WAIT_FRAMES
  LDA LOOPN
  CMP #7
  BCS .wd_r
  INC LOOPN
.wd_r:
  RTS

; a new stage for the player playing: no acorn taken, the first one shines
NEW_STAGE_P:
  STZ TAKEN
  STZ TAKEN+1
  STZ TAKEN+2
  STZ LITI
  STZ CHAINN
  LDA #1
  STA MULT
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
  TXA                          ; extra byte: the stage reached (round x 15 + stage + 1)
  ASL A
  ASL A
  ASL A
  ASL A
  TAY
  LDA PSAVE+1,Y
  ASL A
  ASL A
  ASL A
  ASL A
  SEC
  SBC PSAVE+1,Y
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
REC_NAME:  .byte "SKY SQUIRREL    "
REC_HEAD:  .byte "BEST SQUIRRELS",0
REC_XLBL:  .byte "STAGE ",0


; ===============================================================
;  HUD: row 0 (scores), row 1 (stage, player, multiplier, lives)
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

; row 1: STAGE nn, PLAYER n, the multiplier, the spare lives
DRAW_STATUS:
  LDX #1
  LDY #0
  JSR NT_XY
  LDX #0
.ds_s:
  LDA TXT_STAGEH,X
  STA VDATA
  INX
  CPX #6
  BNE .ds_s
  LDA SCRN
  INC A
  JSR PUT_NUM
  LDA #$20
  STA VDATA
  LDA NPL
  CMP #2
  BNE .ds_m
  LDX #1
  LDY #10
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
.ds_m:
  LDX #1                       ; the multiplier: x2 ... x5
  LDY #20
  JSR NT_XY
  LDA #$20
  LDX #$20
  LDY MULT
  CPY #2
  BCC .ds_mw
  TYA
  ORA #$30
  TAX
  LDA #T_MULT
.ds_mw:
  STA VDATA
  STX VDATA
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

UPDATE_HUD:                    ; HUDD bits: 1 score, 2 the status row
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
SAVE_PLAYER:                   ; player CURP
  LDA CURP
  ASL A
  ASL A
  ASL A
  ASL A
  TAX
  LDY #0
.sp_b:
  LDA SCRN,Y
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
  STA SCRN,Y
  INX
  INY
  CPY #PBLOCK
  BNE .lp_b
  RTS

; A = points (BCD tens and units), Y = hundreds and thousands: MULT times (keeps X)
ADD_PTS_M:
  STA PTS_L
  STY PTS_M
  STZ PTS_H
  LDA MULT
  STA MLOOP
.am_l:
  JSR ADD_SCORE
  DEC MLOOP
  BNE .am_l
  RTS

; A = points (BCD tens and units), Y = hundreds and thousands
ADD_PTS:
  STA PTS_L
  STY PTS_M
  STZ PTS_H
  ; fall into ADD_SCORE

; PTS_L / PTS_M / PTS_H (BCD) to the player playing; a life more at 30000, then every 60000
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
  SED
  LDA NEXTX
  CLC
  ADC #$06
  CLD
  BCC .as_x
  LDA #$FF                     ; past 990000: no more
.as_x:
  STA NEXTX
  JSR LIFE_UP
.as_d:
  LDA #1
  TSB HUDD
  PLY
  PLX
  RTS

; a life more to the player playing (at most 7)
LIFE_UP:
  PHX
  LDX CURP
  LDA LIVES,X
  CMP #7
  BCS .lu_m
  INC LIVES,X
.lu_m:
  LDA #2
  TSB HUDD
  LDA #W_EXTRA
  LDX #2
  JSR SFX_WHISTLE
  PLX
  RTS


; ===============================================================
;  THE STAGE ON THE SCREEN
; ===============================================================
; the tiles of the place, BACK (backdrop + platforms), MAP (+ the acorns left),
; the acorns of the layout, MAP to the name table (interrupt off)
DRAW_STAGE:
  LDA SCRN                     ; the place: 3 stages each
  LDX #0
.ds_f:
  CMP #3
  BCC .ds_t
  SBC #3
  INX
  BRA .ds_f
.ds_t:
  STX BACKN
  LDX SCRN
  LDA LY_LO,X
  STA LYPTR
  LDA LY_HI,X
  STA LYPTR+1
  JSR LOAD_BACK
  ; ---- the backdrop: rows 0-1 spaces, rows 2-23 from the runs
  LDA #$20
  LDX #63
.ds_h:
  STA BACK,X
  DEX
  BPL .ds_h
  LDX BACKN
  LDA BKM_LO,X
  STA PTR2
  LDA BKM_HI,X
  STA PTR2+1
  LDA #<(BACK+64)
  STA PTR
  LDA #>(BACK+64)
  STA PTR+1
.ds_r:
  LDY #0
  LDA (PTR2),Y                 ; count (0 = end)
  BEQ .ds_p
  TAX
  INY
  LDA (PTR2),Y                 ; tile
  DEY
.ds_w:
  STA (PTR),Y
  INC PTR
  BNE .ds_wn
  INC PTR+1
.ds_wn:
  DEX
  BNE .ds_w
  LDA PTR2
  CLC
  ADC #2
  STA PTR2
  BCC .ds_r
  INC PTR2+1
  BRA .ds_r
  ; ---- the platforms: row, first column, tiles
.ds_p:
  LDY #0
  LDA (LYPTR),Y
  STA T5                       ; platforms left
  INY
.ds_pl:
  LDA T5
  BEQ .ds_ac
  LDA (LYPTR),Y
  STA HITR
  INY
  LDA (LYPTR),Y
  STA T2                       ; first column
  INY
  LDA (LYPTR),Y
  STA T3                       ; tiles
  INY
  STY T4
  JSR BACK_PTR
  LDY T2
  LDA #T_PLATL
  STA (PTR),Y
.ds_pm:
  INY
  DEC T3
  LDA T3
  CMP #1
  BEQ .ds_pr
  LDA #T_PLATM
  STA (PTR),Y
  BRA .ds_pm
.ds_pr:
  LDA #T_PLATR
  STA (PTR),Y
  LDY T4
  DEC T5
  BRA .ds_pl
  ; ---- the acorns: columns, rows, the shining order, Pip
.ds_ac:
  LDX #0
.ds_a1:
  LDA (LYPTR),Y
  STA AC_C,X
  ASL A
  ASL A
  ASL A
  STA AC_X,X
  INY
  INX
  CPX #24
  BNE .ds_a1
  LDX #0
.ds_a2:
  LDA (LYPTR),Y
  STA AC_R,X
  ASL A
  ASL A
  ASL A
  STA AC_Y,X
  INY
  INX
  CPX #24
  BNE .ds_a2
  LDX #0
.ds_a3:
  LDA (LYPTR),Y
  STA CHAIN,X
  INY
  INX
  CPX #24
  BNE .ds_a3
  LDA (LYPTR),Y
  STA PSX
  INY
  LDA (LYPTR),Y
  STA PSY
  ; ---- BACK to MAP
  LDX #0
.ds_c:
  LDA BACK,X
  STA MAP,X
  LDA BACK+$100,X
  STA MAP+$100,X
  LDA BACK+$200,X
  STA MAP+$200,X
  INX
  BNE .ds_c
  ; ---- the acorns left into MAP (the shining one shines)
  STZ NLEFT
  LDX #23
.ds_k:
  TXA
  LSR A
  LSR A
  LSR A
  TAY
  TXA
  AND #7
  PHY
  TAY
  LDA BITS,Y
  PLY
  AND TAKEN,Y
  BEQ .ds_kl
  LDA #1
  STA AC_T,X
  BRA .ds_kn
.ds_kl:
  STZ AC_T,X
  INC NLEFT
  LDA #T_ACORN
  JSR MAP_ACORN
.ds_kn:
  DEX
  BPL .ds_k
  LDY LITI
  CPY #24
  BCS .ds_v
  LDX CHAIN,Y
  LDA #T_LIT
  JSR MAP_ACORN
  ; ---- MAP to the name table
.ds_v:
  LDA #$00
  STA VREG
  LDA #($38 | VDP_WRITE_VRAM_BIT)
  STA VREG
  LDA #<MAP
  STA PTR
  LDA #>MAP
  STA PTR+1
  LDX #3
  LDY #0
.ds_vv:
  LDA (PTR),Y
  STA VDATA
  INY
  BNE .ds_vv
  INC PTR+1
  DEX
  BNE .ds_vv
  RTS

; the 32 tiles of the place BACKN (128-159) in the three thirds: patterns and colours
LOAD_BACK:
  LDX #0
.lb_t:
  STX T7
  LDY BACKN
  LDA BKP_LO,Y
  STA PTR
  LDA BKP_HI,Y
  STA PTR+1
  STZ T0
  LDA LB_PAT,X
  STA T1
  STZ T2
  LDA #1
  STA T3
  JSR VCOPY
  LDY BACKN
  LDA BKC_LO,Y
  STA PTR
  LDA BKC_HI,Y
  STA PTR+1
  STZ T0
  LDX T7
  LDA LB_PAT,X
  CLC
  ADC #$20
  STA T1
  STZ T2
  LDA #1
  STA T3
  JSR VCOPY
  LDX T7
  INX
  CPX #3
  BNE .lb_t
  RTS
LB_PAT:     .byte $44,$4C,$54          ; tile 128 of the three thirds (with the write bit)

; X = acorn, A = first tile: its 4 tiles into MAP (keeps X)
MAP_ACORN:
  STA T0
  LDA AC_R,X
  STA HITR
  JSR ROW_PTR
  LDY AC_C,X
  LDA T0
  STA (PTR),Y
  INC A
  INY
  STA (PTR),Y
  INC A
  PHA
  TYA
  CLC
  ADC #31
  TAY
  PLA
  STA (PTR),Y
  INC A
  INY
  STA (PTR),Y
  RTS

; X = acorn, A = first tile (0 = the backdrop under it): its 4 tiles into MAP and the
; name table (interrupt off, keeps X)
PUT_ACORN:
  STA T0
  PHX
  LDA AC_R,X
  STA HITR
  LDA AC_C,X
  STA HITC
  JSR PA_ROW
  INC HITR
  LDA T0
  BEQ .pa_b
  INC T0
  INC T0
.pa_b:
  JSR PA_ROW
  PLX
  RTS

; two cells of row HITR from column HITC: tiles T0, T0+1 (T0 = 0: the backdrop)
PA_ROW:
  JSR ROW_PTR
  LDA PTR
  STA PTR2
  LDA PTR+1
  CLC
  ADC #(>BACK - >MAP)
  STA PTR2+1
  LDX HITR
  LDY HITC
  JSR NT_XY
  LDY HITC
  LDA T0
  BNE .pr_1
  LDA (PTR2),Y
.pr_1:
  STA (PTR),Y
  STA VDATA
  INY
  LDA T0
  BEQ .pr_2
  INC A
  BRA .pr_3
.pr_2:
  LDA (PTR2),Y
.pr_3:
  STA (PTR),Y
  STA VDATA
  RTS

; HITR = row: PTR = its row of MAP (keeps X, Y)
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

; HITR = row: PTR = its row of BACK (keeps X, Y)
BACK_PTR:
  JSR ROW_PTR
  LDA PTR+1
  CLC
  ADC #(>BACK - >MAP)
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

; STAGE n, the name of the place, PLAYER n on rows 11, 13, 15
MSG_STAGE:
  LDA #<TXT_STAGE
  STA TP
  LDA #>TXT_STAGE
  STA TP+1
  JSR PRINT
  LDA SCRN
  INC A
  JSR PUT_NUM
  LDA #$20
  STA VDATA
  LDX #13                      ; the name of the place
  LDY #9
  JSR NT_XY
  LDA BACKN
  ASL A
  STA T0
  ASL A
  ASL A
  ASL A
  SEC
  SBC T0
  TAX                          ; x 14
  LDY #14
.ms_n:
  LDA BACK_TXT,X
  STA VDATA
  INX
  DEY
  BNE .ms_n
  LDA NPL
  CMP #2
  BNE .ms_r
  LDA #<TXT_PLAYER
  STA TP
  LDA #>TXT_PLAYER
  STA TP+1
  JSR PRINT
  LDA CURP
  CLC
  ADC #$31
  STA VDATA
.ms_r:
  RTS

; the rows of the messages back to the stage
MSG_CLEAR:
  LDX #11
  JSR PUT_MAPROW
  LDX #13
  JSR PUT_MAPROW
  LDX #15
  JMP PUT_MAPROW


; ===============================================================
;  A STAGE BEGINS: the foes, the timers, Pip
; ===============================================================
STAGE_INIT:
  LDX #NOB-1
.si_o:
  STZ O_K,X
  DEX
  BPL .si_o
  STZ NENEM
  STZ SPAWNN
  STZ POWERT
  STZ GOLDON
  STZ GOLDC
  STZ GLOWS
  LDA #LEAF_S
  STA LEAFT
  LDA #59
  STA SECF
  LDA LOOPN                    ; faster with the place and the round
  ASL A
  CLC
  ADC BACKN
  CMP #7
  BCC .si_s
  LDA #7
.si_s:
  STA SPDBASE
  LDA SCRN                     ; owls at most: 1 on stages 1-5, then 2, one more a round (3 at most)
  CMP #5
  LDA #1
  ADC LOOPN
  CMP #4
  BCC .si_w
  LDA #3
.si_w:
  STA OWLMAX
  LDX SCRN                     ; foes at most: 2, 3, 4, 5, 6 (3 stages each), one more a round
  LDA SCRN_3,X
  CLC
  ADC #2
  ADC LOOPN
  CMP #7
  BCC .si_m
  LDA #6
.si_m:
  STA MAXEN
  LDA SCRN                     ; a foe every 230 - 8 x stage - 25 x round frames, 80 at least
  ASL A
  ASL A
  ASL A
  STA T0
  LDA LOOPN
  ASL A
  ASL A
  ASL A
  ASL A
  CLC
  ADC LOOPN
  ADC LOOPN
  ADC LOOPN
  ADC LOOPN
  ADC LOOPN
  ADC LOOPN
  ADC LOOPN
  ADC LOOPN
  ADC LOOPN
  ADC T0
  BCS .si_i0
  STA T0
  LDA #230
  SEC
  SBC T0
  BCC .si_i0
  CMP #80
  BCS .si_i
.si_i0:
  LDA #80
.si_i:
  STA SPAWNI
  STA SPAWNT
  ; ---- Pip at the start
  LDA PSX
  STA PX
  LDA PSY
  STA PY
  STZ PXF
  STZ PYF
  STZ PVYL
  STZ PVYH
  STZ PTH
  STZ PGL
  STZ PDIR
  STZ PMV
  LDA #1
  STA PST
  LDA #90
  STA PINV
  JSR NEW_SPAWN                ; two foes coming in at once
  JMP NEW_SPAWN


; ===============================================================
;  PIP: run, jump, glide
; ===============================================================
PIP:
  LDA PINV
  BEQ .pi_i
  DEC PINV
.pi_i:
  LDA PST
  CMP #3
  BNE .pi_m
  JMP PIP_HIT
.pi_m:
  ; ---- left and right: 1.5 pixels a frame on a platform, 1.25 in the air, 1 gliding
  STZ PMV
  LDX #0
  LDA PST
  CMP #1
  BEQ .pi_sp
  INX
  LDA PGL
  BEQ .pi_sp
  INX
.pi_sp:
  LDA RUN_L,X
  STA T0
  LDA RUN_H,X
  STA T1
  LDA JOYC
  AND #$0C
  CMP #$04
  BEQ .pi_l
  CMP #$08
  BNE .pi_v
  STZ PDIR                     ; right
  INC PMV
  CLC
  LDA PXF
  ADC T0
  STA PXF
  LDA PX
  ADC T1
  CMP #X_MAX+1
  BCC .pi_xs
  LDA #X_MAX
  BRA .pi_xs
.pi_l:
  LDA #1                       ; left
  STA PDIR
  STA PMV
  SEC
  LDA PXF
  SBC T0
  STA PXF
  LDA PX
  SBC T1
  BCC .pi_xm
  CMP #X_MIN
  BCS .pi_xs
.pi_xm:
  LDA #X_MIN
.pi_xs:
  STA PX
.pi_v:
  LDA PST
  CMP #1
  BNE .pi_air
  ; ---- on a platform: the jump (button 1 or UP pressed now)
  LDA JOYC
  AND #$11
  BEQ .pi_sup
  LDA JOYP
  AND #$11
  BNE .pi_sup
  LDA #JUMP_L
  STA PVYL
  LDA #JUMP_H
  STA PVYH
  LDA #THRUST
  STA PTH
  STZ PGL
  LDA #2
  STA PST
  LDA #W_JUMP
  LDX #2
  JSR SFX_WHISTLE
  BRA .pi_mv
.pi_sup:
  LDA PX                       ; nothing under the feet: he falls
  LDY PY
  JSR SUPPORT
  BCS .pi_r
  LDA #2
  STA PST
  STZ PVYL
  STZ PVYH
  STZ PTH
  STZ PGL
.pi_r:
  RTS
  ; ---- in the air
.pi_air:
  LDA PTH
  BEQ .pi_fall
  DEC PTH                      ; thrust while button 1 or UP is held (a tap: a few frames)
  LDA PTH
  CMP #THRUST-THRUST_MIN
  BCS .pi_mv
  LDA JOYC
  AND #$11
  BNE .pi_mv
  STZ PTH
.pi_fall:
  LDA JOYC                     ; gliding: button 1 pressed again, while it is held
  AND #$10
  BNE .pi_g1
  STZ PGL
  BRA .pi_gr
.pi_g1:
  LDA JOYP
  AND #$10
  BNE .pi_gr
  LDA PGL
  BNE .pi_gr
  INC PGL
  LDA #W_GLIDE
  LDX #2
  JSR SFX_WHISTLE
.pi_gr:
  CLC                          ; gravity
  LDA PVYL
  ADC #GRAV
  STA PVYL
  LDA PVYH
  ADC #0
  STA PVYH
  BMI .pi_mv
  LDX #0                       ; the fastest fall: gliding, DOWN, or else
  LDA PGL
  BNE .pi_cap
  INX
  LDA JOYC
  AND #$02
  BEQ .pi_cap
  INX
.pi_cap:
  LDA PVYH
  CMP CAP_H,X
  BCC .pi_mv
  BNE .pi_cc
  LDA PVYL
  CMP CAP_L,X
  BCC .pi_mv
.pi_cc:
  LDA CAP_L,X
  STA PVYL
  LDA CAP_H,X
  STA PVYH
.pi_mv:
  CLC                          ; y moves
  LDA PYF
  ADC PVYL
  STA PYF
  LDA PY
  ADC PVYH
  STA PY
  LDA PVYH
  BPL .pi_dn
  LDA PY                       ; going up: never into the ceiling
  CMP #Y_MIN
  BCC .pi_top
  CMP #200
  BCC .pi_r2
.pi_top:
  LDA #Y_MIN
  STA PY
  STZ PVYL
  STZ PVYH
  STZ PTH
  RTS
.pi_dn:
  LDA PX                       ; coming down: the feet on a platform
  LDY PY
  JSR LANDING
  BCC .pi_r2
  STA PY
  STZ PYF
  STZ PVYL
  STZ PVYH
  STZ PGL
  STZ PTH
  LDA #1
  STA PST
.pi_r2:
  RTS

; hit: up a little, then down through everything and out of the screen
PIP_HIT:
  LDA PY
  CMP #200
  BCS .ph_r
  CLC
  LDA PVYL
  ADC #GRAV
  STA PVYL
  LDA PVYH
  ADC #0
  STA PVYH
  CLC
  LDA PYF
  ADC PVYL
  STA PYF
  LDA PY
  ADC PVYH
  STA PY
.ph_r:
  RTS

; a foe (or a thing) touches Pip: the life is lost (global: the tests)
LOSE_NOW:
  LDA PINV
  BNE .ln_r
  LDY OI
  LDA O_K,Y
  STA DEATH
  LDA #3
  STA PST
  LDA #$FE
  STA PVYH
  STZ PVYL
  LDA #1
  STA GSTATE
  LDA #150
  STA GT
  INC LOSTN
  LDA #W_DIE
  LDX #2
  JSR SFX_WHISTLE
.ln_r:
  RTS


; ===============================================================
;  THE PLATFORMS: collisions with the tiles
; ===============================================================
; HITR / HITC: A = the tile of MAP there
TILE_AT:
  JSR ROW_PTR
  LDY HITC
  LDA (PTR),Y
  RTS

; A = tile: C = 1 if one can stand on it (the floor, a platform)
SOLID:
  CMP #T_FLOOR
  BCC .so_n
  CMP #T_PLATR+1
  BCS .so_n
  SEC
  RTS
.so_n:
  CLC
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
  BCS .ld_n
  STA T7
  AND #7
  CMP #4
  BCS .ld_n
  LDY T7
  LDA T6
  JSR SUPPORT_F
  BCC .ld_r
  LDA T7
  AND #$F8
  SEC
  SBC #16
  SEC
  RTS
.ld_n:
  CLC
.ld_r:
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
  JSR SOLID
  BCS .sf_r
  LDA T6
  CLC
  ADC #11
  LSR A
  LSR A
  LSR A
  STA HITC
  JSR TILE_AT
  JMP SOLID
.sf_r:
  RTS


; ===============================================================
;  THE ACORNS
; ===============================================================
; Pip takes the acorns he touches
ACORNS:
  LDA PST
  CMP #3
  BCS .ac_r
  LDX #23
.ac_l:
  LDA AC_T,X
  BNE .ac_n
  LDA AC_X,X
  SEC
  SBC PX
  CLC
  ADC #11
  CMP #22
  BCS .ac_n
  LDA AC_Y,X
  SEC
  SBC PY
  CLC
  ADC #11
  CMP #22
  BCS .ac_n
  JSR TAKE_ACORN
.ac_n:
  DEX
  BPL .ac_l
.ac_r:
  RTS

; X = acorn taken (keeps X)
TAKE_ACORN:
  LDA #1
  STA AC_T,X
  TXA                          ; its bit in TAKEN
  LSR A
  LSR A
  LSR A
  TAY
  TXA
  AND #7
  PHX
  TAX
  LDA BITS,X
  ORA TAKEN,Y
  STA TAKEN,Y
  PLX
  DEC NLEFT
  INC ACN
  LDA #0
  JSR PUT_ACORN
  LDY LITI                     ; the shining one?
  CPY #24
  BCS .ta_u
  TXA
  CMP CHAIN,Y
  BNE .ta_u
  INC CHAINN
  LDA #$00
  LDY #$02
  JSR ADD_PTS_M
  LDA #W_LIT
  PHX
  LDX #2
  JSR SFX_WHISTLE
  PLX
  JSR NEXT_LIT
  BRA .ta_g
.ta_u:
  LDA #$00
  LDY #$01
  JSR ADD_PTS_M
  LDA #W_ACORN
  PHX
  LDX #2
  JSR SFX_WHISTLE
  PLX
.ta_g:
  INC GOLDC                    ; now and then the gold acorn
  LDA GOLDC
  CMP #GOLD_N
  BCC .ta_e
  LDA GOLDON
  ORA POWERT
  BNE .ta_e
  STZ GOLDC
  PHX
  JSR NEW_GOLD
  PLX
.ta_e:
  LDA NLEFT                    ; the last one: the stage is done
  BNE .ta_r
  LDA #3
  STA GSTATE
  LDA #50
  STA GT
.ta_r:
  RTS

; the next acorn of the shining order still there shines (keeps X)
NEXT_LIT:
  PHX
  LDY LITI
.nl_l:
  INY
  CPY #24
  BCS .nl_none
  LDX CHAIN,Y
  LDA AC_T,X
  BNE .nl_l
  STY LITI
  LDA #T_LIT
  JSR PUT_ACORN
  PLX
  RTS
.nl_none:
  LDA #24
  STA LITI
  PLX
  RTS

; every 8 frames the shining acorn flashes
GLOW:
  LDA FRAME_CNT
  AND #7
  BNE .gw_r
  LDY LITI
  CPY #24
  BCS .gw_r
  LDA GLOWS
  EOR #1
  STA GLOWS
  LDX CHAIN,Y
  LDA #T_LIT
  LDY GLOWS
  BEQ .gw_p
  LDA #T_FLASH
.gw_p:
  JMP PUT_ACORN
.gw_r:
  RTS


; ===============================================================
;  THE CLOCK: the gold acorn, the foes coming in, the leaves
; ===============================================================
CLOCK:
  LDA POWERT
  BEQ .ck_s
  LDA FRAME_CNT
  AND #1
  BNE .ck_s
  DEC POWERT
.ck_s:
  DEC SPAWNT                   ; a foe comes in
  BNE .ck_l
  LDA SPAWNI
  STA SPAWNT
  LDA NENEM
  CMP MAXEN
  BCS .ck_l
  JSR NEW_SPAWN
.ck_l:
  DEC SECF                     ; ---- once a second
  BPL .ck_r
  LDA #59
  STA SECF
  DEC LEAFT
  BNE .ck_r
  LDA #LEAF_S
  STA LEAFT
  JMP NEW_LEAF
.ck_r:
  RTS

; a foe comes in from one of the three doors on top (not the one over Pip)
NEW_SPAWN:
  LDA SPAWNN
  STA T4
  LDY #3
.ns_d:
  LDA T4                       ; door = T4 mod 3
.ns_m:
  CMP #3
  BCC .ns_dd
  SBC #3
  BRA .ns_m
.ns_dd:
  TAX
  LDA DOOR_X,X
  STA T2
  SEC
  SBC PX
  CLC
  ADC #40
  CMP #80
  BCS .ns_ok
  LDA PY
  CMP #72
  BCS .ns_ok
  INC T4
  DEY
  BNE .ns_d
.ns_ok:
  LDA #Y_MIN
  STA T3
  LDA BACKN                    ; the kind: 4 of the place, in turn
  ASL A
  ASL A
  STA T0
  LDA SPAWNN
  AND #3
  ORA T0
  TAY
  LDA EN_KIND,Y
  STA T5
  LDA #K_SPAWN
  JSR NEW_OBJ
  BCS .ns_r
  LDA T5
  STA O_H,X
  LDA #45
  STA O_T,X
  INC NENEM
  INC SPAWNN
  LDA #W_SPAWN
  LDX #2
  JMP SFX_WHISTLE
.ns_r:
  RTS

; the gold acorn: from a door on top, it wanders for 10 s
NEW_GOLD:
  JSR NEXT_RND
  AND #1
  TAX
  LDA GOLD_X,X
  STA T2
  LDA #Y_MIN+8
  STA T3
  LDA #K_GOLD
  JSR NEW_OBJ
  BCS .ng_r
  LDA #150
  STA O_T,X
  JSR NEXT_RND
  AND #1
  STA O_D,X
  LDA #1
  STA GOLDON
.ng_r:
  RTS

; a leaf floats down: X (one time more) or, now and then, 1UP
NEW_LEAF:
  JSR NEXT_RND
  AND #127
  CLC
  ADC #56
  STA T2
  LDA #Y_MIN
  STA T3
  LDA #K_LEAF
  JSR NEW_OBJ
  BCS .nf_r
  JSR NEXT_RND
  AND #3
  BNE .nf_x
  LDA #1                       ; 1 in 4: 1UP
  STA O_H,X
.nf_x:
  LDA MULT                     ; the multiplier at 5: 1UP
  CMP #5
  BCC .nf_r
  LDA #1
  STA O_H,X
.nf_r:
  RTS


; ===============================================================
;  FOES AND THINGS
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
  ASL A
  TAY
  LDA OBJ_JT-2,Y
  STA PTR
  LDA OBJ_JT-1,Y
  STA PTR+1
  JSR .ob_go
.ob_n:
  LDX OI
  DEX
  BPL .ob_l
  RTS
.ob_go:
  JMP (PTR)

OBJ_JT:     .word OWL,WASP,HOG,CROW,CONE,SPAWN,GOLD,LEAF,PUFF

; X = foe: T0 = the fraction, T1 = the pixels of its speed (slow while the gold acorn works)
SPEED_OF:
  LDY O_LV,X
SPEED_Y:                       ; (Y = the level)
  LDA POWERT
  BEQ .so_v
  LDY #0
.so_v:
  LDA SPD_L,Y
  STA T0
  LDA SPD_H,Y
  STA T1
  RTS

; X = object: the steps of T0 / T1 (C = 1: it stopped at the border; keeps X)
GO_RIGHT:
  CLC
  LDA O_XF,X
  ADC T0
  STA O_XF,X
  LDA O_X,X
  ADC T1
  CMP #X_MAX
  BCC .gr_s
  LDA #X_MAX
  STA O_X,X
  SEC
  RTS
.gr_s:
  STA O_X,X
  CLC
  RTS
GO_LEFT:
  SEC
  LDA O_XF,X
  SBC T0
  STA O_XF,X
  LDA O_X,X
  SBC T1
  BCC .gl_b
  CMP #X_MIN
  BCS .gl_s
.gl_b:
  LDA #X_MIN
  STA O_X,X
  SEC
  RTS
.gl_s:
  STA O_X,X
  CLC
  RTS
GO_DOWN:
  CLC
  LDA O_YF,X
  ADC T0
  STA O_YF,X
  LDA O_Y,X
  ADC T1
  CMP #FLOOR_Y
  BCC .gd_s
  LDA #FLOOR_Y
  STA O_Y,X
  SEC
  RTS
.gd_s:
  STA O_Y,X
  CLC
  RTS
GO_UP:
  SEC
  LDA O_YF,X
  SBC T0
  STA O_YF,X
  LDA O_Y,X
  SBC T1
  BCC .gu_b
  CMP #Y_MIN
  BCS .gu_s
.gu_b:
  LDA #Y_MIN
  STA O_Y,X
  SEC
  RTS
.gu_s:
  STA O_Y,X
  CLC
  RTS

; X = object: a step on the slant (bit 0 of O_D left, bit 1 up), back from the borders
SLANT:
  LDA O_D,X
  AND #1
  BNE .sl_l
  JSR GO_RIGHT
  BRA .sl_x
.sl_l:
  JSR GO_LEFT
.sl_x:
  BCC .sl_y
  LDA O_D,X
  EOR #1
  STA O_D,X
.sl_y:
  LDA O_D,X
  AND #2
  BNE .sl_u
  JSR GO_DOWN
  BRA .sl_e
.sl_u:
  JSR GO_UP
.sl_e:
  BCC .sl_r
  LDA O_D,X
  EOR #2
  STA O_D,X
.sl_r:
  RTS

; ---------------------------------------------------------------
; an owl: now and then it looks for Pip (away from him while the gold acorn
; works), then swoops straight that way on the slant: it can be dodged
; ---------------------------------------------------------------
OWL:
  DEC O_T,X
  BNE .ow_f
  LDA #OWL_AIM                 ; a new aim
  STA O_T,X
  LDA PX                       ; bit 0: Pip on the left
  CMP O_X,X
  LDA #0
  ROL A
  EOR #1
  STA T4
  LDA PY                       ; bit 1: Pip above
  CMP O_Y,X
  LDA #0
  ROL A
  EOR #1
  ASL A
  ORA T4
  LDY POWERT
  BEQ .ow_d
  EOR #3
.ow_d:
  STA O_D,X
.ow_f:
  LDY O_LV,X                   ; the owls of the odd slots a level slower: they part
  TXA
  LSR A
  BCC .ow_v
  TYA
  BEQ .ow_v
  DEY
.ow_v:
  JSR SPEED_Y
  LSR T1                       ; half the speed of the others
  ROR T0
  JMP SLANT

; C = 1 if there are owls enough already (keeps X)
OWLS_FULL:
  STZ T4
  LDY #NOB-1
.of_l:
  LDA O_K,Y
  CMP #K_OWL
  BEQ .of_c
  CMP #K_SPAWN
  BNE .of_n
  LDA O_H,Y
  CMP #K_OWL
  BNE .of_n
.of_c:
  INC T4
.of_n:
  DEY
  BPL .of_l
  LDA T4
  CMP OWLMAX
  RTS

; ---------------------------------------------------------------
; a wasp: across the stage, wobbling, a little nearer to Pip
; ---------------------------------------------------------------
WASP:
  JSR SPEED_OF
  LDA O_D,X
  AND #1
  BNE .wa_l
  JSR GO_RIGHT
  BRA .wa_b
.wa_l:
  JSR GO_LEFT
.wa_b:
  BCC .wa_y
  LDA O_D,X
  EOR #1
  STA O_D,X
.wa_y:
  INC O_T,X
  LDA #1
  STA T1
  STZ T0
  LDA O_T,X
  AND #1
  BNE .wa_d
  LDA O_T,X                    ; the wobble
  AND #16
  BNE .wa_wu
  JMP GO_DOWN
.wa_wu:
  JMP GO_UP
.wa_d:
  LDA O_T,X                    ; every 8 frames a pixel nearer to Pip (away with the gold acorn)
  AND #7
  CMP #1
  BNE .wa_r
  LDA PY
  CMP O_Y,X
  BEQ .wa_r
  LDA #0
  ROL A
  LDY POWERT
  BEQ .wa_p
  EOR #1
.wa_p:
  CMP #0
  BEQ .wa_pu
  JMP GO_DOWN
.wa_pu:
  JMP GO_UP
.wa_r:
  RTS

; ---------------------------------------------------------------
; a crow: on the slant, back from the borders
; ---------------------------------------------------------------
CROW:
  JSR SPEED_OF
  JMP SLANT

; ---------------------------------------------------------------
; a hedgehog walks along the platforms and falls from their ends; on the
; ground for a while, it becomes an owl. A pine cone hops all the time.
; ---------------------------------------------------------------
HOG:
CONE:
  LDA O_S,X
  BEQ .hg_g
  JMP WK_AIR
.hg_g:
  JSR WALK_X
  LDA O_K,X
  CMP #K_CONE
  BNE .hg_h
  LDA #$00                     ; a hop: -2 pixels a frame
  STA O_VYL,X
  LDA #$FE
  STA O_VYH,X
  LDA #1
  STA O_S,X
  RTS
.hg_h:
  LDA O_Y,X                    ; on the ground: the time to fly
  CMP #FLOOR_Y
  BNE .hg_s
  DEC O_T,X
  BNE .hg_s
  LDA #200                     ; owls enough: it walks on
  STA O_T,X
  JSR OWLS_FULL
  BCS .hg_s
  LDA #1
  STA O_T,X
  LDA #K_OWL
  STA O_K,X
  LDA #W_SPAWN
  PHX
  LDX #2
  JSR SFX_WHISTLE
  PLX
  RTS
.hg_s:
  LDA O_X,X                    ; nothing under the feet: it falls
  LDY O_Y,X
  JSR SUPPORT
  BCS .hg_r
  LDA #1
  STA O_S,X
  STZ O_VYL,X
  STZ O_VYH,X
.hg_r:
  RTS

WK_AIR:
  JSR WALK_X
  CLC                          ; gravity, down at 2 pixels a frame at most
  LDA O_VYL,X
  ADC #GRAV
  STA O_VYL,X
  LDA O_VYH,X
  ADC #0
  BMI .wk_v
  CMP #2
  BCC .wk_v
  LDA #0
  STA O_VYL,X
  LDA #2
.wk_v:
  STA O_VYH,X
  CLC
  LDA O_YF,X
  ADC O_VYL,X
  STA O_YF,X
  LDA O_Y,X
  ADC O_VYH,X
  STA O_Y,X
  LDA O_VYH,X
  BMI .wk_c
  LDA O_X,X
  LDY O_Y,X
  JSR LANDING
  BCC .wk_r
  STA O_Y,X
  STZ O_YF,X
  STZ O_VYL,X
  STZ O_VYH,X
  STZ O_S,X
.wk_r:
  RTS
.wk_c:
  LDA O_Y,X                    ; going up: never into the ceiling
  CMP #Y_MIN
  BCC .wk_cc
  CMP #200
  BCC .wk_r
.wk_cc:
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
  JSR GO_RIGHT
  BRA .wx_t
.wx_l:
  JSR GO_LEFT
.wx_t:
  BCC .wx_r
  LDA O_D,X
  EOR #1
  STA O_D,X
.wx_r:
  RTS

; ---------------------------------------------------------------
; a foe coming in: a spark, then the foe
; ---------------------------------------------------------------
SPAWN:
  DEC O_T,X
  BNE .sp_r
  LDA O_H,X                    ; an owl, if there are not owls enough already (else a hedgehog)
  CMP #K_OWL
  BNE .sp_k
  STZ O_K,X
  JSR OWLS_FULL
  LDA #K_OWL
  BCC .sp_k
  LDA #K_HOG
.sp_k:
  STA O_K,X
  LDA SPDBASE
  STA O_LV,X
  JSR NEXT_RND
  AND #1
  STA O_D,X                    ; left or right, going down
  LDA #200                     ; a hedgehog flies after 200 frames on the ground
  STA O_T,X
  LDA O_K,X
  CMP #K_OWL
  BNE .sp_o
  LDA #1                       ; an owl aims at once
  STA O_T,X
.sp_o:
  CMP #K_HOG
  BCC .sp_r
  CMP #K_CROW
  BEQ .sp_r
  LDA #1                       ; hedgehogs and cones fall in
  STA O_S,X
.sp_r:
  RTS

; ---------------------------------------------------------------
; the gold acorn: on the slant at 0.75 pixels a frame for 10 s
; ---------------------------------------------------------------
GOLD:
  LDA FRAME_CNT
  AND #3
  BNE .go_m
  DEC O_T,X
  BNE .go_m
  STZ O_K,X
  STZ GOLDON
  RTS
.go_m:
  LDA #$C0
  STA T0
  STZ T1
  JMP SLANT

; ---------------------------------------------------------------
; a leaf: down slowly, swinging, then a while on the ground
; ---------------------------------------------------------------
LEAF:
  LDA O_S,X
  BEQ .lf_f
  DEC O_T,X                    ; on the ground: 3 s
  BNE .lf_r
  STZ O_K,X
.lf_r:
  RTS
.lf_f:
  LDA #$60
  STA T0
  STZ T1
  JSR GO_DOWN
  BCC .lf_s
  LDA #1
  STA O_S,X
  LDA #180
  STA O_T,X
  RTS
.lf_s:
  INC O_T,X                    ; the swing: 64 frames each way
  LDA #$80
  STA T0
  LDA O_T,X
  AND #64
  BNE .lf_l
  JMP GO_RIGHT
.lf_l:
  JMP GO_LEFT

; a nut taken: the puff goes away
PUFF:
  DEC O_T,X
  BNE .pf_r
  STZ O_K,X
.pf_r:
  RTS


; ===============================================================
;  TOUCHES: Pip against the foes and the things
; ===============================================================
TOUCHES:
  LDA PST
  CMP #3
  BCS .to_r
  LDY #NOB-1
.to_o:
  LDA O_K,Y
  BEQ .to_n
  CMP #K_SPAWN
  BEQ .to_n
  CMP #K_PUFF
  BEQ .to_n
  LDA O_X,Y                    ; 10 pixels apart at most
  SEC
  SBC PX
  CLC
  ADC #10
  CMP #20
  BCS .to_n
  LDA O_Y,Y
  SEC
  SBC PY
  CLC
  ADC #10
  CMP #20
  BCS .to_n
  STY OI
  JSR TOUCH
  LDA PST
  CMP #3
  BCS .to_r
  LDY OI
.to_n:
  DEY
  BPL .to_o
.to_r:
  RTS

; Pip touches object OI
TOUCH:
  LDX OI
  LDA O_K,X
  CMP #K_GOLD
  BNE .tc_l
  STZ O_K,X                    ; the gold acorn: the foes are nuts for 6 s
  STZ GOLDON
  LDA #POWER_T
  STA POWERT
  STZ NUTN
  LDA #$00
  LDY #$10
  JSR ADD_PTS
  LDA #W_GOLD
  LDX #2
  JMP SFX_WHISTLE
.tc_l:
  CMP #K_LEAF
  BNE .tc_f
  STZ O_K,X                    ; a leaf: one time more, or a life
  LDA O_H,X
  BNE .tc_up
  LDA MULT
  CMP #5
  BCS .tc_lp
  INC MULT
  LDA #2
  TSB HUDD
.tc_lp:
  LDA #$00
  LDY #$10
  JSR ADD_PTS
  LDA #W_LEAF
  LDX #2
  JMP SFX_WHISTLE
.tc_up:
  LDA #$00
  LDY #$10
  JSR ADD_PTS
  JMP LIFE_UP
.tc_f:
  LDA POWERT                   ; a foe: a nut to take, or a life lost
  BNE .tc_nut
  JMP LOSE_NOW
.tc_nut:
  LDA #K_PUFF
  STA O_K,X
  LDA #20
  STA O_T,X
  DEC NENEM
  INC NUTS
  LDY NUTN
  CPY #4
  BCS .tc_np
  INC NUTN
.tc_np:
  LDA #$00
  LDX NUTPTS,Y
  TXA
  TAY
  LDA #$00
  JSR ADD_PTS_M
  LDA #W_NUT
  LDX #2
  JSR SFX_WHISTLE
  LDA #S_POP
  LDX #2
  JMP SFX_BOOM


; ===============================================================
;  SPRITES: Pip and the objects take turns
; ===============================================================
BUILD_SAT:
  STZ SPRI
  LDA FRAME_CNT
  AND #1
  BEQ .bs_p
  JSR SAT_OBJS
  JSR SAT_PIP
  BRA .bs_e
.bs_p:
  JSR SAT_PIP
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

; Pip: the belly on top of the fur
SAT_PIP:
  LDA PY
  CMP #192
  BCS .sp_r
  LDA PINV                     ; blinking
  AND #4
  BNE .sp_r
  LDA PX
  STA OX
  LDA PY
  STA OY
  LDA PST                      ; the picture
  CMP #3
  BNE .sp_a
  LDA #PT_DIZZY
  BRA .sp_d
.sp_a:
  CMP #1
  BNE .sp_air
  LDA #PT_STAND
  LDY PMV
  BEQ .sp_d
  LDA FRAME_CNT
  AND #8
  BEQ .sp_r1
  LDA #PT_RUN2
  BRA .sp_d
.sp_r1:
  LDA #PT_RUN1
  BRA .sp_d
.sp_air:
  LDA #PT_GLIDE
  LDY PGL
  BNE .sp_d
  LDA #PT_JUMP
  LDY PVYH
  BMI .sp_d
  LDA #PT_FALL
.sp_d:
  LDY PDIR
  BEQ .sp_p
  CLC
  ADC #PT_LEFT
.sp_p:
  STA T5
  CLC
  ADC #4                       ; the belly: white
  STA ON
  LDA #15
  STA OC
  JSR ADD_SPR
  LDA T5                       ; the fur: orange
  STA ON
  LDA #9
  STA OC
  JMP ADD_SPR
.sp_r:
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
  LDA FRAME_CNT                ; 2 pictures: T0 = 0 / 4
  AND #8
  LSR A
  STA T0
  CPY #K_SPAWN
  BCS .ol_t
  LDA POWERT                   ; a foe under the gold acorn: a nut (it blinks at the end)
  BEQ .ol_f
  CMP #40
  BCS .ol_nut
  LDA FRAME_CNT
  AND #8
  BNE .ol_f
.ol_nut:
  LDA #PT_NUT
  STA ON
  LDA #10
  STA OC
  RTS
.ol_f:
  LDA KPAT,Y
  CPY #K_HOG                   ; hedgehogs and crows look where they go
  BEQ .ol_d
  CPY #K_CROW
  BNE .ol_2
.ol_d:
  PHA
  LDA O_D,X
  AND #1
  BEQ .ol_dr
  PLA
  CLC
  ADC #8
  BRA .ol_2
.ol_dr:
  PLA
.ol_2:
  CLC
  ADC T0
  STA ON
  RTS
.ol_t:
  CPY #K_LEAF
  BNE .ol_g
  LDA #PT_LEAFX                ; a leaf: X green, 1UP cyan
  LDY O_H,X
  BEQ .ol_lx
  LDA #7
  STA OC
  LDA #PT_LEAF1
.ol_lx:
  STA ON
  RTS
.ol_g:
  CPY #K_GOLD
  BNE .ol_s
  LDA T0
  BEQ .ol_g1
  LDA #15
  STA OC
.ol_g1:
  LDA #PT_GOLD1
  CLC
  ADC T0
  STA ON
  RTS
.ol_s:
  LDA KPAT,Y                   ; the spark and the puff blink
  STA ON
  LDA FRAME_CNT
  AND #4
  BEQ .ol_r
  LDA #7
  STA OC
.ol_r:
  RTS


; ===============================================================
;  SCREEN: VRAM, texts, sprites, sound (from wormer)
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
; Pip: left and right on a platform, in the air, gliding (1.5, 1.25, 1 pixels a frame)
RUN_L:      .byte $80,$40,$00
RUN_H:      .byte $01,$01,$01
; the fastest fall: gliding, falling, DOWN held (0.5, 2.5, 3.5 pixels a frame)
CAP_L:      .byte GLIDE_MAXL,FALL_MAXL,DIVE_MAXL
CAP_H:      .byte GLIDE_MAX,FALL_MAX,DIVE_MAX
; speed of the levels 0-7: 0.5, 0.625, 0.75, 0.875, 1, 1.25, 1.5, 1.75 pixels a frame
SPD_L:      .byte $80,$A0,$C0,$E0,$00,$40,$80,$C0
SPD_H:      .byte $00,$00,$00,$00,$01,$01,$01,$01
; per kind: -, owl, wasp, hedgehog, crow, cone, spark, gold acorn, leaf, puff
KCOL:       .byte 0,15,11,14,13,8,15,11,3,15
KPAT:       .byte 0,PT_OWL1,PT_WASP1,PT_HOG1,PT_CROW1,PT_CONE1,PT_SPARK,PT_GOLD1,PT_LEAFX,PT_PUFF
NUTPTS:     .byte $02,$04,$08,$16,$20          ; nuts: 200 400 800 1600 2000 (BCD hundreds)
DOOR_X:     .byte 40,120,200                   ; where the foes come in (on top)
GOLD_X:     .byte 72,168
; the foes of every place, in turn
EN_KIND:
  .byte K_OWL,K_HOG,K_OWL,K_CONE               ; the oak wood
  .byte K_WASP,K_HOG,K_CROW,K_WASP             ; the waterfall
  .byte K_CROW,K_CONE,K_OWL,K_HOG              ; the old mill
  .byte K_CROW,K_OWL,K_WASP,K_CROW             ; the city roofs
  .byte K_OWL,K_CROW,K_CONE,K_WASP             ; the snow peaks
SCRN_3:     .byte 0,0,0,1,1,1,2,2,2,3,3,3,4,4,4   ; stage / 3
BOB_T:      .byte 0,1,2,3,3,2,1,0              ; Pip on the title, up and down

; title: Pip (belly, fur), an owl, a crow, the gold acorn, a leaf (sprite Y, X, pattern, colour)
TITLE_NS = 6
TITLE_SY:   .byte 47,47,47,47,119,139
TITLE_SX:   .byte 120,120,40,200,4,4
TITLE_SN:   .byte PT_GLIDEB,PT_GLIDE,PT_OWL1,PT_CROWL1,PT_GOLD1,PT_LEAFX
TITLE_SC:   .byte 15,9,15,13,11,3

TXT_STAGEH: .byte "STAGE "
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
  .byte 9,1,"JUMP HIGH AND GLIDE DOWN SLOWLY",0
  .byte 10,0,"TO TAKE THE 24 ACORNS OF A STAGE",0
  .byte 12,3,T_ACORN,T_ACORN+1,0
  .byte 13,3,T_ACORN+2,T_ACORN+3,0
  .byte 12,6,"ACORN 100",0
  .byte 12,17,T_LIT,T_LIT+1,0
  .byte 13,17,T_LIT+2,T_LIT+3,0
  .byte 12,20,"SHINING 200",0
  .byte 14,1,"TAKE THEM IN TURN: CHAIN BONUS",0
  .byte 16,3,"GOLD ACORN: FOES TURN TO NUTS",0
  .byte 18,3,"LEAVES: X POINTS, 1UP A LIFE",0
  .byte $FF
TXT_STAGE:
  .byte 11,12,"STAGE ",0,$FF
TXT_PLAYER:
  .byte 15,12,"PLAYER ",0,$FF
TXT_CLEAR:
  .byte 11,8,"ALL THE ACORNS!",0
  .byte 13,11,"CHAIN ",0
  .byte $FF
TXT_PERFECT:
  .byte 15,6,"PERFECT CHAIN 50000",0,$FF
TXT_WORLD:
  .byte 17,6,"THE ACORNS ARE HOME",0,$FF
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
;  GRAPHICS, STAGES AND SOUND TABLES (generated)
; ===============================================================
; SKY SQUIRREL: generated by dev/gen_sky_squirrel.js (do not edit by hand)

; sprite patterns (16x16), value = pattern number * 4
PT_STAND = 0
PT_STANDB = 4
PT_RUN1 = 8
PT_RUN1B = 12
PT_RUN2 = 16
PT_RUN2B = 20
PT_JUMP = 24
PT_JUMPB = 28
PT_GLIDE = 32
PT_GLIDEB = 36
PT_FALL = 40
PT_FALLB = 44
PT_DIZZY = 48
PT_DIZZYB = 52
PT_STANDL = 56
PT_STANDLB = 60
PT_RUN1L = 64
PT_RUN1LB = 68
PT_RUN2L = 72
PT_RUN2LB = 76
PT_JUMPL = 80
PT_JUMPLB = 84
PT_GLIDEL = 88
PT_GLIDELB = 92
PT_FALLL = 96
PT_FALLLB = 100
PT_DIZZYL = 104
PT_DIZZYLB = 108
PT_OWL1 = 112
PT_OWL2 = 116
PT_WASP1 = 120
PT_WASP2 = 124
PT_HOG1 = 128
PT_HOG2 = 132
PT_HOGL1 = 136
PT_HOGL2 = 140
PT_CROW1 = 144
PT_CROW2 = 148
PT_CROWL1 = 152
PT_CROWL2 = 156
PT_CONE1 = 160
PT_CONE2 = 164
PT_NUT = 168
PT_GOLD1 = 172
PT_GOLD2 = 176
PT_LEAFX = 180
PT_LEAF1 = 184
PT_PUFF = 188
PT_SPARK = 192
PT_LEFT = PT_STANDL-PT_STAND
SPR_LEN = 1568
SPR_PAGES = 7
SPRITES:
  .byte $00,$00,$00,$38,$7C,$C6,$82,$82,$C3,$67,$37,$1F,$0F,$0C,$1C,$00,$00,$00,$12,$1E,$37,$3F,$7C,$9C,$1C,$1C,$18,$E0,$E0,$C0,$E0,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$60,$E0,$E0,$E0,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$38,$7C,$C6,$82,$82,$C3,$67,$37,$1F,$1F,$30,$60,$00,$00,$00,$12,$1E,$37,$3F,$7C,$9C,$1C,$1C,$18,$E0,$E0,$30,$18,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$60,$E0,$E0,$E0,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$38,$7C,$C6,$82,$82,$C3,$67,$37,$1F,$07,$06,$0C,$00,$00,$00,$12,$1E,$37,$3F,$7C,$9C,$1C,$1C,$18,$E0,$C0,$C0,$C0,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$60,$E0,$E0,$E0,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$08,$11,$21,$23,$27,$37,$1F,$0F,$0D,$18,$30,$00,$24,$3C,$6C,$7C,$FC,$38,$38,$38,$30,$E0,$E0,$80,$80,$C0,$40,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$C0,$C0,$C0,$C0,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$C0,$70,$3F,$1E,$0E,$07,$02,$00,$00,$00,$00,$00,$00,$00,$09,$1F,$1B,$3F,$FF,$0F,$0E,$FC,$08,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$01,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$F0,$F0,$00,$00,$00,$00,$00,$00
  .byte $00,$10,$10,$20,$20,$24,$34,$1D,$0F,$07,$03,$01,$01,$03,$00,$00,$00,$12,$1E,$37,$3F,$7C,$9C,$9E,$1A,$18,$F0,$E0,$20,$30,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$60,$60,$E0,$E0,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$0F,$1F,$3C,$38,$2B,$35,$2B,$1F,$0F,$04,$0C,$00,$00,$00,$00,$00,$F0,$F8,$3C,$1C,$D4,$AC,$D4,$F8,$F0,$20,$30,$00,$00,$00
  .byte $00,$00,$00,$00,$03,$07,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$C0,$E0,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$48,$78,$EC,$FC,$3E,$39,$38,$38,$18,$07,$07,$03,$07,$00,$00,$00,$00,$1C,$3E,$63,$41,$41,$C3,$E6,$EC,$F8,$F0,$30,$38,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$06,$07,$07,$07,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$48,$78,$EC,$FC,$3E,$39,$38,$38,$18,$07,$07,$0C,$18,$00,$00,$00,$00,$1C,$3E,$63,$41,$41,$C3,$E6,$EC,$F8,$F8,$0C,$06,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$06,$07,$07,$07,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$48,$78,$EC,$FC,$3E,$39,$38,$38,$18,$07,$03,$03,$03,$00,$00,$00,$00,$1C,$3E,$63,$41,$41,$C3,$E6,$EC,$F8,$E0,$60,$30,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$06,$07,$07,$07,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $24,$3C,$36,$3E,$3F,$1C,$1C,$1C,$0C,$07,$07,$01,$01,$03,$02,$00,$00,$00,$00,$00,$10,$88,$84,$C4,$E4,$EC,$F8,$F0,$B0,$18,$0C,$00
  .byte $00,$00,$00,$00,$00,$03,$03,$03,$03,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$90,$F8,$D8,$FC,$FF,$F0,$70,$3F,$10,$00,$00,$00,$00,$00,$00,$00,$00,$00,$03,$0E,$FC,$78,$70,$E0,$40,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$0F,$0F,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$80,$80,$00,$00,$00,$00,$00,$00
  .byte $00,$48,$78,$EC,$FC,$3E,$39,$79,$58,$18,$0F,$07,$04,$0C,$00,$00,$00,$08,$08,$04,$04,$24,$2C,$B8,$F0,$E0,$C0,$80,$80,$C0,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$06,$06,$07,$07,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$0F,$1F,$3C,$38,$2B,$35,$2B,$1F,$0F,$04,$0C,$00,$00,$00,$00,$00,$F0,$F8,$3C,$1C,$D4,$AC,$D4,$F8,$F0,$20,$30,$00,$00,$00
  .byte $00,$00,$00,$00,$03,$07,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$C0,$E0,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $88,$CF,$F9,$76,$3F,$0E,$0D,$0F,$0B,$07,$02,$06,$00,$00,$00,$00,$11,$F3,$9F,$6E,$FC,$70,$B0,$F0,$D0,$E0,$40,$60,$00,$00,$00,$00
  .byte $08,$0F,$19,$16,$3F,$7E,$ED,$CF,$8B,$07,$02,$06,$00,$00,$00,$00,$10,$F0,$98,$68,$FC,$7E,$B7,$F3,$D1,$E0,$40,$60,$00,$00,$00,$00
  .byte $18,$3C,$3E,$1E,$07,$0D,$1D,$2E,$0D,$06,$03,$01,$00,$00,$00,$00,$30,$78,$F8,$F0,$C0,$60,$70,$E8,$60,$C0,$80,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$60,$F7,$76,$1D,$2E,$0D,$06,$03,$01,$00,$00,$00,$00,$00,$00,$18,$3C,$DC,$F8,$70,$E8,$60,$C0,$80,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$15,$2A,$55,$6A,$AA,$55,$FF,$7F,$30,$30,$00,$00,$00,$00,$00,$00,$40,$A0,$58,$BC,$B7,$7F,$F6,$E0,$60,$60,$00,$00
  .byte $00,$00,$00,$00,$15,$2A,$55,$6A,$AA,$55,$FF,$7F,$18,$0C,$00,$00,$00,$00,$00,$00,$40,$A0,$58,$BC,$B7,$7F,$F6,$E0,$C0,$60,$00,$00
  .byte $00,$00,$00,$00,$02,$05,$1A,$3D,$ED,$FE,$6F,$07,$06,$06,$00,$00,$00,$00,$00,$00,$A8,$54,$AA,$56,$55,$AA,$FF,$FE,$0C,$0C,$00,$00
  .byte $00,$00,$00,$00,$02,$05,$1A,$3D,$ED,$FE,$6F,$07,$03,$06,$00,$00,$00,$00,$00,$00,$A8,$54,$AA,$56,$55,$AA,$FF,$FE,$18,$30,$00,$00
  .byte $00,$00,$06,$0F,$0F,$07,$03,$07,$0F,$1F,$3F,$74,$C1,$00,$00,$00,$00,$00,$00,$00,$80,$C0,$E0,$F7,$FD,$FB,$80,$40,$80,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$07,$1F,$7F,$F9,$C3,$07,$0E,$00,$00,$00,$00,$00,$00,$00,$1C,$3D,$FE,$F8,$FC,$F8,$E0,$80,$00,$00,$00
  .byte $00,$00,$00,$00,$01,$03,$07,$EF,$BF,$DF,$01,$02,$01,$00,$00,$00,$00,$00,$60,$F0,$F0,$E0,$C0,$E0,$F0,$F8,$FC,$2E,$83,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$38,$BC,$7F,$1F,$3F,$1F,$07,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$E0,$F8,$FE,$9F,$C3,$E0,$70,$00,$00
  .byte $01,$03,$05,$0D,$15,$1A,$2A,$35,$2A,$1A,$15,$0D,$05,$03,$00,$00,$00,$80,$40,$60,$50,$B0,$A8,$58,$A8,$B0,$50,$60,$40,$80,$00,$00
  .byte $00,$00,$00,$35,$5A,$AD,$D6,$AD,$5A,$35,$00,$00,$00,$00,$00,$00,$00,$00,$00,$58,$B4,$6A,$D7,$6A,$B4,$58,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$03,$0F,$1F,$15,$3F,$37,$3F,$3F,$1F,$0F,$07,$01,$00,$00,$00,$00,$C0,$F0,$F8,$54,$FC,$F6,$FA,$FC,$F8,$F0,$E0,$80,$00,$00
  .byte $01,$00,$1F,$3F,$55,$7F,$3F,$3F,$2F,$2F,$1F,$1F,$0F,$07,$03,$01,$80,$80,$F8,$FC,$56,$FE,$FC,$FC,$FC,$F8,$F8,$F0,$F0,$E0,$C0,$80
  .byte $01,$00,$1F,$3F,$00,$7F,$3F,$3F,$2F,$00,$1F,$1F,$0F,$07,$03,$01,$80,$80,$F8,$FC,$00,$FE,$FC,$FC,$FC,$00,$F8,$F0,$F0,$E0,$C0,$80
  .byte $01,$03,$07,$0F,$17,$3B,$3C,$7C,$7B,$37,$3F,$1F,$0F,$03,$01,$01,$00,$80,$C0,$E0,$B0,$78,$F8,$FC,$7C,$B8,$F8,$F0,$E0,$80,$00,$00
  .byte $01,$03,$07,$0F,$1F,$2A,$0A,$6A,$6A,$2D,$3F,$1F,$0F,$03,$01,$01,$00,$80,$C0,$E0,$F0,$98,$A8,$9C,$BC,$B8,$F8,$F0,$E0,$80,$00,$00
  .byte $00,$00,$10,$08,$45,$20,$07,$CF,$07,$20,$45,$08,$10,$00,$00,$00,$00,$00,$40,$84,$10,$08,$C0,$E6,$C0,$08,$10,$84,$40,$00,$00,$00
  .byte $00,$00,$00,$00,$01,$01,$05,$03,$3E,$03,$05,$01,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$40,$80,$F8,$80,$40,$00,$00,$00,$00,$00

; fixed game tiles 96-111: patterns and colours
TILEP:
  .byte $01,$00,$1F,$3F,$55,$7F,$3F,$3F,$80,$80,$F8,$FC,$56,$FE,$FC,$FC,$2F,$2F,$1F,$1F,$0F,$07,$03,$01,$FC,$F8,$F8,$F0,$F0,$E0,$C0,$80
  .byte $01,$00,$1F,$3F,$55,$7F,$3F,$3F,$80,$80,$F8,$FC,$56,$FE,$FC,$FC,$2F,$2F,$1F,$1F,$0F,$07,$03,$01,$FC,$F8,$F8,$F0,$F0,$E0,$C0,$80
  .byte $00,$42,$7E,$DB,$FF,$7E,$3C,$00,$00,$C6,$6C,$38,$6C,$C6,$00,$00,$01,$00,$1F,$3F,$55,$7F,$3F,$3F,$80,$80,$F8,$FC,$56,$FE,$FC,$FC
  .byte $2F,$2F,$1F,$1F,$0F,$07,$03,$01,$FC,$F8,$F8,$F0,$F0,$E0,$C0,$80,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
TILEC:
  .byte $61,$61,$61,$61,$61,$61,$61,$A1,$61,$61,$61,$61,$61,$61,$61,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1
  .byte $91,$91,$91,$91,$91,$91,$91,$B1,$91,$91,$91,$91,$91,$91,$91,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $91,$91,$91,$91,$91,$91,$91,$91,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11
TILE_FIRST = 96
TILE_N = 16

; the backdrops: tiles 128-159 (patterns and colours), the picture of rows 2-23 in runs
BKP0:
  .byte $B6,$A6,$B4,$B6,$36,$A6,$B2,$B6,$AA,$FF,$DD,$FF,$BB,$FF,$6E,$FF,$7F,$A5,$7F,$00,$00,$00,$00,$00,$FF,$49,$FF,$02,$00,$00,$00,$00
  .byte $FE,$A5,$FE,$00,$00,$00,$00,$00,$00,$00,$08,$00,$00,$00,$00,$00,$00,$20,$70,$20,$00,$00,$00,$00,$03,$0F,$1F,$3F,$3F,$6F,$7F,$7E
  .byte $C0,$E0,$70,$78,$F8,$F8,$F8,$F0,$7F,$3F,$3F,$1F,$0F,$03,$00,$00,$F0,$E0,$F0,$F0,$E0,$C0,$00,$00,$5A,$4A,$6A,$5A,$52,$5A,$4A,$6A
  .byte $5A,$53,$69,$5A,$52,$DA,$8A,$6A,$B7,$FF,$DB,$FF,$77,$FF,$ED,$FF,$00,$18,$3C,$7E,$5E,$FF,$DB,$FF,$FF,$DB,$FE,$6E,$4C,$08,$00,$00
  .byte $00,$00,$00,$00,$44,$55,$DD,$FF,$00,$00,$10,$28,$10,$12,$35,$12,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
BKC0:
  .byte $61,$61,$61,$61,$61,$61,$61,$61,$C1,$C1,$6C,$61,$61,$61,$61,$61,$A1,$6A,$61,$11,$11,$11,$11,$11,$A1,$6A,$61,$C1,$11,$11,$11,$11
  .byte $A1,$6A,$61,$11,$11,$11,$11,$11,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$51,$51,$51,$51,$51,$51,$51,$51,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
  .byte $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$61,$61,$61,$61,$61,$61,$61,$61
  .byte $61,$61,$61,$61,$61,$61,$61,$61,$C1,$C1,$C1,$C1,$C1,$C1,$C1,$C1,$C1,$C1,$C1,$C1,$C1,$C1,$C1,$C1,$C1,$C1,$C1,$C1,$C1,$C1,$C1,$C1
  .byte $C1,$C1,$C1,$C1,$C1,$C1,$C1,$C1,$11,$11,$91,$91,$91,$C1,$C1,$C1,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11
  .byte $11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11
  .byte $11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11
  .byte $11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11
BKM0:
  .byte $20,$81,$01,$80,$15,$20,$01,$85,$08,$20,$02,$80,$08,$20,$01,$85,$0B,$20,$01,$87,$01,$88,$08,$20,$02,$80,$0D,$20,$01,$86,$06,$20
  .byte $01,$89,$01,$8A,$08,$20,$02,$80,$01,$20,$04,$8E,$04,$20,$01,$86,$0A,$20,$01,$85,$01,$20,$01,$86,$04,$20,$01,$86,$02,$20,$02,$80
  .byte $06,$8D,$0A,$20,$01,$85,$07,$20,$04,$8E,$02,$20,$02,$80,$06,$8D,$01,$20,$01,$85,$09,$20,$01,$85,$05,$20,$06,$8D,$01,$20,$02,$80
  .byte $06,$8D,$06,$20,$04,$8E,$05,$20,$01,$85,$01,$20,$06,$8D,$01,$20,$02,$80,$01,$8F,$04,$8D,$01,$8F,$05,$20,$06,$8D,$06,$20,$06,$8D
  .byte $01,$20,$02,$80,$02,$20,$02,$8B,$07,$20,$06,$8D,$06,$20,$01,$8F,$04,$8D,$01,$8F,$01,$20,$02,$80,$02,$20,$02,$8B,$07,$20,$06,$8D
  .byte $08,$20,$02,$8B,$03,$20,$02,$80,$02,$20,$02,$8B,$07,$20,$01,$8F,$04,$8D,$01,$8F,$08,$20,$02,$8B,$03,$20,$02,$80,$02,$20,$02,$8B
  .byte $09,$20,$02,$8B,$0A,$20,$02,$8B,$03,$20,$02,$80,$02,$20,$01,$8C,$01,$8B,$09,$20,$01,$8C,$01,$8B,$0A,$20,$01,$8C,$01,$8B,$03,$20
  .byte $02,$80,$02,$20,$02,$8B,$09,$20,$02,$8B,$0A,$20,$02,$8B,$03,$20,$02,$80,$02,$20,$02,$8B,$09,$20,$02,$8B,$0A,$20,$02,$8B,$03,$20
  .byte $02,$80,$02,$20,$02,$8B,$09,$20,$02,$8B,$0A,$20,$02,$8B,$03,$20,$02,$80,$02,$20,$02,$8B,$09,$20,$02,$8B,$0A,$20,$02,$8B,$03,$20
  .byte $02,$80,$02,$20,$01,$8C,$01,$8B,$09,$20,$01,$8C,$01,$8B,$0A,$20,$01,$8C,$01,$8B,$03,$20,$02,$80,$02,$20,$02,$8B,$09,$20,$02,$8B
  .byte $0A,$20,$02,$8B,$03,$20,$02,$80,$01,$90,$01,$91,$06,$90,$01,$91,$06,$90,$01,$91,$06,$90,$01,$91,$06,$90,$01,$91,$01,$80,$20,$81
  .byte $00
BKP1:
  .byte $DD,$BB,$77,$EE,$DD,$BB,$77,$EE,$FF,$B7,$FF,$55,$AA,$55,$AA,$55,$7F,$FF,$6B,$20,$00,$00,$00,$00,$FF,$FF,$B5,$44,$00,$00,$00,$00
  .byte $FE,$FF,$D6,$04,$00,$00,$00,$00,$00,$00,$08,$00,$00,$00,$00,$00,$00,$20,$70,$20,$00,$00,$00,$00,$DE,$BD,$7B,$F7,$EF,$DE,$BD,$7B
  .byte $02,$07,$0F,$1E,$3D,$7B,$F7,$EF,$40,$E0,$F0,$78,$BC,$DE,$EF,$F7,$94,$94,$A4,$A5,$A9,$A9,$4A,$4A,$4A,$4A,$92,$94,$A4,$A4,$A9,$94
  .byte $AA,$55,$DB,$7E,$FF,$6E,$B7,$FF,$00,$66,$99,$00,$33,$CC,$00,$66,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
BKC1:
  .byte $41,$41,$41,$41,$41,$41,$41,$41,$E1,$E4,$41,$54,$45,$54,$45,$54,$F1,$E1,$E1,$E1,$11,$11,$11,$11,$F1,$E1,$E1,$E1,$11,$11,$11,$11
  .byte $F1,$E1,$E1,$E1,$11,$11,$11,$11,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$71,$71,$71,$71,$71,$71,$71,$71,$41,$41,$41,$41,$41,$41,$41,$41
  .byte $41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$41,$54,$54,$54,$54,$54,$54,$54,$54,$74,$74,$74,$74,$74,$74,$74,$74
  .byte $F4,$F4,$74,$74,$54,$54,$54,$54,$54,$54,$54,$54,$54,$54,$54,$54,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11
  .byte $11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11
  .byte $11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11
  .byte $11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11
  .byte $11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11
BKM1:
  .byte $20,$81,$01,$80,$01,$87,$01,$89,$09,$20,$01,$8A,$01,$8B,$01,$8A,$01,$8B,$01,$8A,$01,$8B,$01,$8A,$02,$20,$01,$85,$07,$20,$01,$88
  .byte $01,$87,$02,$80,$01,$87,$01,$89,$01,$86,$08,$20,$01,$8B,$01,$8A,$01,$8B,$01,$8A,$01,$8B,$01,$8A,$01,$8B,$05,$20,$01,$85,$04,$20
  .byte $01,$88,$01,$87,$02,$80,$01,$87,$01,$89,$07,$20,$01,$86,$01,$20,$01,$8A,$01,$8B,$01,$8A,$01,$8B,$01,$8A,$01,$8B,$01,$8A,$01,$85
  .byte $09,$20,$01,$88,$01,$87,$02,$80,$01,$87,$01,$89,$09,$20,$01,$8B,$01,$8A,$01,$8B,$01,$8A,$01,$8B,$01,$8A,$01,$8B,$08,$20,$01,$86
  .byte $01,$20,$01,$88,$01,$87,$02,$80,$01,$87,$01,$89,$03,$20,$01,$85,$04,$20,$01,$85,$01,$8A,$01,$8B,$01,$8A,$01,$8B,$01,$8A,$01,$8B
  .byte $01,$8A,$05,$20,$01,$85,$04,$20,$01,$88,$01,$87,$02,$80,$02,$87,$01,$89,$08,$20,$01,$8B,$01,$8A,$01,$8B,$01,$8A,$01,$8B,$01,$8A
  .byte $01,$8B,$09,$20,$01,$88,$02,$87,$02,$80,$02,$87,$01,$89,$08,$20,$01,$8A,$01,$8B,$01,$8A,$01,$8B,$01,$8A,$01,$8B,$01,$8A,$09,$20
  .byte $01,$88,$02,$87,$02,$80,$02,$87,$01,$89,$08,$20,$01,$8B,$01,$8A,$01,$8B,$01,$8A,$01,$8B,$01,$8A,$01,$8B,$09,$20,$01,$88,$02,$87
  .byte $02,$80,$02,$87,$01,$89,$08,$20,$01,$8A,$01,$8B,$01,$8A,$01,$8B,$01,$8A,$01,$8B,$01,$8A,$09,$20,$01,$88,$02,$87,$02,$80,$02,$87
  .byte $01,$89,$08,$20,$01,$8B,$01,$8A,$01,$8B,$01,$8A,$01,$8B,$01,$8A,$01,$8B,$09,$20,$01,$88,$02,$87,$02,$80,$02,$87,$01,$89,$08,$20
  .byte $01,$8A,$01,$8B,$01,$8A,$01,$8B,$01,$8A,$01,$8B,$01,$8A,$09,$20,$01,$88,$02,$87,$02,$80,$03,$87,$01,$89,$07,$20,$01,$8B,$01,$8A
  .byte $01,$8B,$01,$8A,$01,$8B,$01,$8A,$01,$8B,$08,$20,$01,$88,$03,$87,$02,$80,$03,$87,$01,$89,$07,$20,$01,$8A,$01,$8B,$01,$8A,$01,$8B
  .byte $01,$8A,$01,$8B,$01,$8A,$08,$20,$01,$88,$03,$87,$02,$80,$03,$87,$01,$89,$07,$20,$01,$8B,$01,$8A,$01,$8B,$01,$8A,$01,$8B,$01,$8A
  .byte $01,$8B,$08,$20,$01,$88,$03,$87,$02,$80,$03,$87,$01,$89,$07,$20,$01,$8A,$01,$8B,$01,$8A,$01,$8B,$01,$8A,$01,$8B,$01,$8A,$08,$20
  .byte $01,$88,$03,$87,$02,$80,$03,$87,$01,$89,$07,$20,$01,$8B,$01,$8A,$01,$8B,$01,$8A,$01,$8B,$01,$8A,$01,$8B,$08,$20,$01,$88,$03,$87
  .byte $02,$80,$03,$87,$01,$89,$07,$20,$01,$8A,$01,$8B,$01,$8A,$01,$8B,$01,$8A,$01,$8B,$01,$8A,$08,$20,$01,$88,$03,$87,$02,$80,$03,$87
  .byte $01,$89,$07,$20,$01,$8B,$01,$8A,$01,$8B,$01,$8A,$01,$8B,$01,$8A,$01,$8B,$08,$20,$01,$88,$03,$87,$02,$80,$03,$87,$01,$89,$05,$20
  .byte $0B,$8C,$06,$20,$01,$88,$03,$87,$02,$80,$03,$87,$01,$89,$16,$8D,$01,$88,$03,$87,$01,$80,$20,$81,$00
BKP2:
  .byte $EF,$EF,$FF,$BF,$BF,$FF,$FB,$FF,$FF,$AA,$FF,$EF,$EF,$EF,$FF,$BF,$7F,$81,$7F,$00,$00,$00,$00,$00,$FF,$10,$FF,$00,$00,$00,$00,$00
  .byte $FE,$81,$FE,$00,$00,$00,$00,$00,$00,$00,$08,$00,$00,$00,$00,$00,$00,$20,$70,$20,$00,$00,$00,$00,$03,$0F,$1F,$3F,$3F,$6F,$7F,$7E
  .byte $C0,$E0,$70,$78,$F8,$F8,$F8,$F0,$7F,$3F,$3F,$1F,$0F,$03,$00,$00,$F0,$E0,$F0,$F0,$E0,$C0,$00,$00,$EF,$EF,$EF,$00,$FE,$FE,$FE,$00
  .byte $00,$02,$16,$36,$FE,$FE,$FE,$00,$7E,$5E,$5E,$5E,$5E,$5E,$5E,$7E,$FF,$BF,$FF,$7E,$5E,$5E,$5E,$7E,$03,$0F,$18,$30,$60,$40,$C0,$80
  .byte $C0,$F0,$18,$0C,$06,$02,$03,$01,$10,$38,$54,$92,$FE,$92,$54,$38,$08,$1C,$2A,$49,$7F,$49,$2A,$1C,$00,$00,$00,$08,$4A,$5A,$DF,$FF
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
BKC2:
  .byte $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$F1,$E1,$E1,$61,$61,$61,$61,$61,$F1,$E1,$E1,$11,$11,$11,$11,$11,$F1,$E1,$E1,$11,$11,$11,$11,$11
  .byte $F1,$E1,$E1,$11,$11,$11,$11,$11,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$51,$51,$51,$51,$51,$51,$51,$51,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1
  .byte $A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$61,$61,$61,$61,$61,$61,$61,$61
  .byte $61,$61,$61,$61,$61,$61,$61,$61,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
  .byte $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$C1,$C1,$C1,$C1,$C1,$C1,$C1,$C1
  .byte $11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11
  .byte $11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11
  .byte $11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11
BKM2:
  .byte $20,$81,$01,$80,$17,$20,$01,$86,$06,$20,$02,$80,$05,$20,$01,$87,$01,$88,$15,$20,$01,$85,$01,$20,$02,$80,$02,$20,$01,$86,$02,$20
  .byte $01,$89,$01,$8A,$0C,$20,$01,$86,$08,$20,$01,$85,$01,$20,$02,$80,$05,$20,$01,$85,$07,$20,$01,$85,$10,$20,$02,$80,$0F,$20,$01,$85
  .byte $0E,$20,$02,$80,$16,$20,$01,$85,$07,$20,$02,$80,$0B,$20,$01,$85,$07,$20,$01,$8C,$01,$20,$02,$8C,$01,$20,$02,$8C,$01,$20,$01,$8C
  .byte $02,$20,$02,$80,$04,$20,$01,$8F,$01,$90,$04,$20,$01,$8F,$01,$90,$07,$20,$01,$8B,$01,$8C,$02,$8B,$01,$8C,$02,$8B,$01,$8C,$01,$8B
  .byte $02,$20,$02,$80,$03,$20,$01,$8F,$02,$20,$01,$90,$02,$20,$01,$8F,$02,$20,$01,$90,$06,$20,$09,$8B,$02,$20,$02,$80,$02,$20,$01,$8E
  .byte $05,$20,$01,$8E,$05,$20,$01,$8E,$04,$20,$09,$8B,$02,$20,$02,$80,$02,$20,$01,$8D,$05,$20,$01,$8D,$05,$20,$01,$8D,$04,$20,$03,$8B
  .byte $01,$91,$01,$92,$04,$8B,$02,$20,$02,$80,$02,$20,$01,$8D,$05,$20,$01,$8D,$05,$20,$01,$8D,$04,$20,$03,$8B,$01,$92,$01,$91,$04,$8B
  .byte $02,$20,$02,$80,$02,$20,$01,$8D,$05,$20,$01,$8D,$05,$20,$01,$8D,$04,$20,$09,$8B,$02,$20,$02,$80,$02,$20,$01,$8D,$05,$20,$01,$8D
  .byte $05,$20,$01,$8D,$04,$20,$09,$8B,$02,$20,$02,$80,$02,$20,$01,$8D,$05,$20,$01,$8D,$05,$20,$01,$8D,$04,$20,$09,$8B,$02,$20,$02,$80
  .byte $02,$20,$01,$8D,$05,$20,$01,$8D,$05,$20,$01,$8D,$04,$20,$03,$8B,$01,$91,$01,$92,$04,$8B,$02,$20,$02,$80,$02,$20,$01,$8D,$05,$20
  .byte $01,$8D,$05,$20,$01,$8D,$04,$20,$03,$8B,$01,$92,$01,$91,$04,$8B,$02,$20,$02,$80,$02,$20,$01,$8D,$05,$20,$01,$8D,$05,$20,$01,$8D
  .byte $04,$20,$09,$8B,$02,$20,$02,$80,$02,$20,$01,$8D,$05,$20,$01,$8D,$05,$20,$01,$8D,$04,$20,$09,$8B,$02,$20,$02,$80,$1E,$93,$01,$80
  .byte $20,$81,$00
BKP3:
  .byte $DB,$DB,$00,$6D,$6D,$00,$DB,$DB,$FF,$55,$FF,$DB,$DB,$00,$6D,$6D,$3F,$7F,$AA,$00,$00,$00,$00,$00,$FF,$FF,$AA,$00,$00,$00,$00,$00
  .byte $FC,$FE,$AA,$00,$00,$00,$00,$00,$00,$00,$08,$00,$00,$00,$00,$00,$00,$20,$70,$20,$00,$00,$00,$00,$03,$0F,$1F,$3F,$3F,$6F,$7F,$7E
  .byte $C0,$E0,$70,$78,$F8,$F8,$F8,$F0,$7F,$3F,$3F,$1F,$0F,$03,$00,$00,$F0,$E0,$F0,$F0,$E0,$C0,$00,$00,$FF,$FF,$DB,$DB,$FF,$FF,$DB,$DB
  .byte $FF,$FF,$DB,$DB,$FF,$FF,$DB,$DB,$00,$00,$00,$00,$FF,$AA,$FF,$FF,$00,$7E,$3C,$3C,$3C,$3C,$FF,$FF,$01,$03,$07,$0F,$1F,$3F,$7F,$FF
  .byte $80,$C0,$E0,$F0,$F8,$FC,$FE,$FF,$08,$08,$1C,$08,$08,$08,$08,$08,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
BKC3:
  .byte $D1,$D1,$D1,$D1,$D1,$D1,$D1,$D1,$F1,$D1,$D1,$61,$61,$11,$61,$61,$91,$81,$61,$11,$11,$11,$11,$11,$91,$81,$61,$11,$11,$11,$11,$11
  .byte $91,$81,$61,$11,$11,$11,$11,$11,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$71,$71,$71,$71,$71,$71,$71,$71,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$41,$41,$41,$41,$41,$41,$41,$41
  .byte $4A,$4A,$4A,$4A,$41,$41,$41,$41,$11,$11,$11,$11,$51,$51,$41,$41,$11,$61,$61,$61,$61,$61,$51,$41,$41,$41,$41,$41,$41,$41,$41,$41
  .byte $41,$41,$41,$41,$41,$41,$41,$41,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11
  .byte $11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11
  .byte $11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11
  .byte $11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11
BKM3:
  .byte $20,$81,$01,$80,$04,$20,$01,$85,$17,$20,$01,$86,$01,$20,$02,$80,$08,$20,$01,$85,$05,$20,$01,$85,$08,$20,$01,$87,$01,$88,$02,$20
  .byte $01,$85,$02,$20,$02,$80,$0F,$20,$01,$86,$07,$20,$01,$89,$01,$8A,$02,$20,$01,$86,$02,$20,$02,$80,$07,$20,$01,$85,$02,$20,$01,$85
  .byte $0A,$20,$01,$86,$08,$20,$02,$80,$05,$20,$01,$85,$03,$20,$01,$91,$13,$20,$01,$85,$02,$80,$07,$20,$01,$8E,$16,$20,$02,$80,$02,$20
  .byte $01,$85,$04,$20,$04,$8D,$0D,$20,$01,$8E,$05,$20,$02,$80,$07,$20,$02,$8B,$01,$8C,$01,$8B,$08,$20,$01,$91,$03,$20,$03,$8D,$04,$20
  .byte $02,$80,$02,$20,$03,$8D,$02,$20,$03,$8B,$01,$8C,$05,$20,$01,$8E,$06,$20,$02,$8B,$01,$8C,$04,$20,$02,$80,$02,$20,$03,$8B,$02,$20
  .byte $04,$8B,$05,$20,$04,$8D,$03,$20,$03,$8B,$04,$20,$02,$80,$02,$20,$01,$8C,$02,$8B,$02,$20,$01,$8C,$03,$8B,$03,$8D,$02,$20,$01,$8B
  .byte $01,$8C,$02,$8B,$03,$20,$03,$8B,$04,$20,$02,$80,$02,$8D,$01,$8B,$01,$8C,$01,$8B,$02,$20,$01,$8B,$01,$8C,$04,$8B,$01,$8C,$02,$20
  .byte $02,$8B,$01,$8C,$01,$8B,$03,$20,$01,$8C,$02,$8B,$02,$8D,$02,$20,$02,$80,$04,$8B,$01,$8C,$02,$20,$02,$8B,$01,$8C,$04,$8B,$02,$20
  .byte $03,$8B,$01,$8C,$03,$8D,$01,$8B,$01,$8C,$03,$8B,$02,$20,$02,$80,$01,$8C,$04,$8B,$02,$8D,$03,$8B,$01,$8C,$03,$8B,$02,$20,$04,$8B
  .byte $01,$8C,$04,$8B,$01,$8C,$02,$8B,$02,$20,$02,$80,$01,$8B,$01,$8C,$04,$8B,$01,$8C,$04,$8B,$01,$8C,$02,$8B,$02,$8D,$01,$8C,$04,$8B
  .byte $01,$8C,$04,$8B,$01,$8C,$01,$8B,$02,$20,$02,$80,$02,$8B,$01,$8C,$04,$8B,$01,$8C,$04,$8B,$01,$8C,$04,$8B,$01,$8C,$04,$8B,$01,$8C
  .byte $04,$8B,$01,$8C,$02,$8D,$02,$80,$03,$8B,$01,$8C,$04,$8B,$01,$8C,$04,$8B,$01,$8C,$04,$8B,$01,$8C,$04,$8B,$01,$8C,$04,$8B,$01,$8C
  .byte $01,$8B,$02,$80,$04,$8B,$01,$8C,$04,$8B,$01,$8C,$04,$8B,$01,$8C,$04,$8B,$01,$8C,$04,$8B,$01,$8C,$04,$8B,$01,$8C,$02,$80,$01,$8C
  .byte $04,$8B,$01,$8C,$04,$8B,$01,$8C,$04,$8B,$01,$8C,$04,$8B,$01,$8C,$04,$8B,$01,$8C,$04,$8B,$02,$80,$01,$8B,$01,$8C,$04,$8B,$01,$8C
  .byte $04,$8B,$01,$8C,$04,$8B,$01,$8C,$04,$8B,$01,$8C,$04,$8B,$01,$8C,$03,$8B,$01,$80,$20,$81,$00
BKP4:
  .byte $AA,$55,$AA,$55,$AA,$55,$AA,$55,$FF,$FF,$B7,$FF,$55,$AA,$55,$AA,$7F,$FF,$5A,$24,$00,$00,$00,$00,$FF,$FF,$B5,$4A,$00,$00,$00,$00
  .byte $FE,$FF,$5A,$24,$00,$00,$00,$00,$00,$00,$08,$00,$00,$00,$00,$00,$00,$20,$70,$20,$00,$00,$00,$00,$01,$03,$07,$0F,$1F,$3F,$7F,$FF
  .byte $80,$C0,$E0,$F0,$F8,$FC,$FE,$FF,$FF,$DF,$FF,$FB,$FF,$7F,$FF,$F7,$01,$03,$07,$0F,$1F,$3F,$6F,$A5,$80,$C0,$E0,$F0,$F8,$FC,$F6,$A5
  .byte $00,$3C,$7E,$FF,$FF,$7E,$00,$00,$00,$1C,$7E,$FE,$FF,$7E,$00,$00,$08,$1C,$1C,$3E,$3E,$7F,$08,$08,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
BKC4:
  .byte $51,$51,$51,$51,$51,$51,$51,$51,$F1,$F1,$7F,$71,$51,$51,$51,$51,$F1,$71,$51,$51,$11,$11,$11,$11,$F1,$71,$51,$51,$11,$11,$11,$11
  .byte $F1,$71,$51,$51,$11,$11,$11,$11,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$71,$71,$71,$71,$71,$71,$71,$71,$D1,$D1,$D1,$D1,$D1,$D1,$D1,$D1
  .byte $D1,$D1,$D1,$D1,$D1,$D1,$D1,$D1,$D1,$D1,$D1,$D1,$D1,$D1,$D1,$D1,$F1,$F1,$F1,$F1,$F1,$F1,$FD,$FD,$F1,$F1,$F1,$F1,$F1,$F1,$FD,$FD
  .byte $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$C1,$C1,$C1,$C1,$C1,$C1,$C1,$C1,$11,$11,$11,$11,$11,$11,$11,$11
  .byte $11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11
  .byte $11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11
  .byte $11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11
  .byte $11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11,$11
BKM4:
  .byte $20,$81,$01,$80,$01,$86,$05,$20,$01,$85,$08,$20,$01,$85,$06,$20,$01,$85,$07,$20,$02,$80,$05,$20,$01,$86,$05,$20,$01,$8C,$01,$8D
  .byte $02,$20,$01,$86,$05,$20,$01,$85,$08,$20,$02,$80,$02,$20,$01,$8C,$01,$8D,$0E,$20,$01,$86,$04,$20,$01,$85,$06,$20,$02,$80,$07,$20
  .byte $01,$85,$12,$20,$01,$8C,$01,$8D,$01,$20,$01,$85,$02,$80,$1E,$20,$02,$80,$02,$20,$01,$85,$12,$20,$01,$8A,$01,$8B,$07,$20,$02,$80
  .byte $01,$20,$01,$85,$04,$20,$01,$85,$0D,$20,$01,$8A,$02,$89,$01,$8B,$06,$20,$02,$80,$06,$20,$01,$8A,$01,$8B,$0B,$20,$01,$8A,$04,$89
  .byte $01,$8B,$05,$20,$02,$80,$05,$20,$01,$8A,$02,$89,$01,$8B,$09,$20,$01,$87,$06,$89,$01,$88,$04,$20,$02,$80,$04,$20,$01,$8A,$04,$89
  .byte $01,$8B,$07,$20,$01,$87,$08,$89,$01,$88,$03,$20,$02,$80,$03,$20,$01,$87,$06,$89,$01,$88,$05,$20,$01,$87,$0A,$89,$01,$88,$02,$20
  .byte $02,$80,$02,$20,$01,$87,$08,$89,$01,$88,$01,$20,$01,$8A,$01,$8B,$01,$87,$0C,$89,$01,$88,$01,$20,$02,$80,$01,$20,$01,$87,$0A,$89
  .byte $01,$8A,$02,$89,$01,$8B,$0D,$89,$01,$88,$02,$80,$01,$87,$0A,$89,$01,$8A,$04,$89,$01,$8B,$0D,$89,$02,$80,$0A,$89,$01,$87,$06,$89
  .byte $01,$88,$0C,$89,$02,$80,$09,$89,$01,$87,$08,$89,$01,$88,$0B,$89,$02,$80,$08,$89,$01,$87,$0A,$89,$01,$88,$0A,$89,$02,$80,$07,$89
  .byte $01,$87,$0C,$89,$01,$88,$09,$89,$02,$80,$06,$89,$01,$87,$0E,$89,$01,$88,$08,$89,$02,$80,$01,$89,$01,$8E,$01,$89,$01,$8E,$01,$89
  .byte $01,$87,$10,$89,$01,$88,$04,$89,$02,$8E,$01,$89,$01,$80,$20,$81,$00
BKP_LO:
  .byte <BKP0,<BKP1,<BKP2,<BKP3,<BKP4
BKP_HI:
  .byte >BKP0,>BKP1,>BKP2,>BKP3,>BKP4
BKC_LO:
  .byte <BKC0,<BKC1,<BKC2,<BKC3,<BKC4
BKC_HI:
  .byte >BKC0,>BKC1,>BKC2,>BKC3,>BKC4
BKM_LO:
  .byte <BKM0,<BKM1,<BKM2,<BKM3,<BKM4
BKM_HI:
  .byte >BKM0,>BKM1,>BKM2,>BKM3,>BKM4
; names of the places (14 characters)
BACK_TXT:
  .byte "THE OAK WOOD  "
  .byte "THE WATERFALL "
  .byte "THE OLD MILL  "
  .byte "THE CITY ROOFS"
  .byte "THE SNOW PEAKS"

; the stages: platforms (count; tile row, first column, tiles), 24 acorn columns, 24 acorn rows
; (top left tile), the shining order, where Pip starts (x, y)
LY0:
  .byte $06,$07,$01,$06,$07,$19,$06,$09,$0D,$06,$0F,$09,$0E,$13,$01,$06,$13,$19,$06,$01,$05,$19,$1D,$0D,$11,$0D,$0F,$11,$03,$1B,$03,$0B
  .byte $0F,$13,$1B,$07,$17,$01,$05,$09,$15,$19,$1D,$03,$03,$03,$03,$05,$05,$07,$07,$07,$0B,$0B,$0D,$0D,$0D,$0D,$0D,$11,$11,$15,$15,$15
  .byte $15,$15,$15,$14,$13,$12,$10,$0B,$09,$0C,$0D,$0E,$0F,$0A,$11,$15,$16,$17,$03,$02,$05,$08,$07,$06,$04,$01,$00,$78,$A8
LY1:
  .byte $08,$07,$03,$02,$07,$0B,$0A,$07,$1B,$02,$0D,$01,$06,$0D,$19,$06,$0F,$0D,$06,$13,$05,$06,$13,$15,$06,$0F,$03,$0B,$13,$1B,$0D,$11
  .byte $01,$05,$19,$1D,$0D,$0F,$11,$05,$09,$15,$19,$01,$05,$09,$15,$19,$1D,$03,$05,$05,$05,$05,$09,$09,$0B,$0B,$0B,$0B,$0D,$0D,$0D,$11
  .byte $11,$11,$11,$15,$15,$15,$15,$15,$15,$14,$13,$12,$0E,$0F,$0B,$0C,$0D,$06,$05,$02,$00,$03,$04,$09,$0A,$11,$10,$15,$16,$17,$08,$07
  .byte $01,$78,$A8
LY2:
  .byte $03,$07,$0D,$06,$0B,$09,$0E,$0F,$05,$16,$0F,$0D,$11,$0B,$13,$09,$15,$07,$17,$05,$0F,$19,$03,$1B,$01,$1D,$0B,$13,$01,$05,$09,$15
  .byte $19,$1D,$03,$05,$05,$07,$07,$09,$09,$0B,$0B,$0D,$0D,$0D,$0F,$0F,$11,$11,$13,$13,$15,$15,$15,$15,$15,$15,$14,$13,$12,$0E,$0C,$09
  .byte $07,$05,$03,$01,$02,$00,$04,$06,$08,$0B,$0D,$0F,$17,$16,$15,$11,$10,$0A,$78,$A8
LY3:
  .byte $0B,$05,$01,$06,$05,$19,$06,$09,$07,$04,$09,$15,$04,$0D,$01,$06,$0D,$19,$06,$0F,$0B,$04,$0F,$11,$04,$13,$05,$04,$13,$0D,$06,$13
  .byte $17,$04,$01,$05,$0F,$19,$1D,$0F,$07,$0F,$17,$01,$1D,$01,$07,$17,$1D,$0B,$13,$05,$0F,$19,$01,$05,$19,$1D,$03,$03,$03,$03,$03,$05
  .byte $07,$07,$07,$09,$09,$0B,$0B,$0B,$0B,$0D,$0D,$11,$11,$11,$15,$15,$15,$15,$12,$11,$15,$14,$0B,$09,$06,$0C,$0F,$10,$0D,$0E,$0A,$08
  .byte $07,$05,$02,$01,$00,$03,$04,$13,$16,$17,$78,$A8
LY4:
  .byte $0A,$05,$05,$06,$05,$15,$06,$09,$01,$04,$09,$0D,$06,$09,$1B,$04,$0D,$07,$06,$0D,$13,$06,$11,$01,$04,$11,$0D,$06,$11,$1B,$04,$05
  .byte $09,$15,$19,$01,$0F,$1D,$07,$0B,$13,$17,$01,$0F,$1D,$05,$09,$15,$19,$01,$05,$09,$15,$19,$1D,$03,$03,$03,$03,$07,$07,$07,$0B,$0B
  .byte $0B,$0B,$0F,$0F,$0F,$13,$13,$13,$13,$15,$15,$15,$15,$15,$15,$14,$0F,$0E,$13,$12,$0B,$07,$08,$09,$0A,$06,$03,$02,$01,$00,$04,$05
  .byte $0C,$10,$15,$16,$11,$17,$0D,$78,$A8
LY5:
  .byte $08,$07,$01,$06,$07,$0D,$06,$07,$19,$06,$0D,$05,$06,$0D,$15,$06,$11,$0D,$06,$13,$01,$02,$13,$1D,$02,$01,$1D,$01,$05,$0D,$0F,$11
  .byte $19,$1D,$0D,$11,$07,$17,$07,$0F,$17,$01,$1D,$01,$05,$09,$15,$19,$1D,$03,$03,$05,$05,$05,$05,$05,$05,$05,$09,$09,$0B,$0B,$0F,$0F
  .byte $0F,$11,$11,$15,$15,$15,$15,$15,$15,$14,$13,$12,$10,$0D,$0B,$09,$0A,$06,$05,$04,$03,$02,$00,$07,$08,$01,$0C,$0F,$0E,$15,$16,$17
  .byte $11,$78,$A8
LY6:
  .byte $0A,$05,$07,$06,$05,$13,$06,$07,$01,$02,$07,$1D,$02,$0B,$0D,$06,$0D,$05,$06,$0D,$15,$06,$11,$01,$04,$11,$1B,$04,$13,$07,$12,$07
  .byte $0B,$0F,$13,$17,$01,$1D,$0D,$0F,$11,$07,$17,$01,$1D,$09,$0D,$11,$15,$01,$05,$09,$15,$19,$1D,$03,$03,$03,$03,$03,$05,$05,$09,$09
  .byte $09,$0B,$0B,$0F,$0F,$11,$11,$11,$11,$15,$15,$15,$15,$15,$15,$14,$13,$12,$0C,$0E,$0F,$10,$11,$15,$16,$17,$0D,$0B,$09,$08,$07,$0A
  .byte $00,$01,$02,$03,$04,$06,$05,$78,$A8
LY7:
  .byte $0A,$05,$03,$02,$05,$1B,$02,$07,$09,$0E,$0B,$01,$04,$0B,$1B,$04,$0D,$09,$06,$0D,$11,$06,$11,$03,$06,$11,$17,$06,$13,$0D,$06,$03
  .byte $1B,$0B,$0F,$13,$01,$0D,$11,$1D,$0B,$13,$05,$0F,$19,$0D,$11,$01,$1D,$01,$05,$09,$15,$19,$1D,$03,$03,$05,$05,$05,$09,$09,$09,$09
  .byte $0B,$0B,$0F,$0F,$0F,$11,$11,$13,$13,$15,$15,$15,$15,$15,$15,$14,$13,$12,$10,$0B,$0C,$0E,$0F,$15,$16,$17,$11,$0D,$0A,$07,$06,$09
  .byte $02,$03,$04,$01,$08,$05,$00,$78,$A8
LY8:
  .byte $07,$07,$05,$06,$07,$15,$06,$0B,$0B,$0A,$0F,$01,$04,$0F,$1B,$04,$13,$05,$0A,$13,$11,$0A,$01,$05,$09,$0D,$11,$15,$19,$1D,$07,$17
  .byte $07,$17,$01,$1D,$07,$0D,$11,$17,$01,$05,$09,$15,$19,$1D,$03,$03,$03,$03,$03,$03,$03,$03,$05,$05,$09,$09,$0D,$0D,$11,$11,$11,$11
  .byte $15,$15,$15,$15,$15,$15,$14,$13,$12,$0E,$0F,$10,$11,$15,$16,$17,$0D,$0B,$09,$05,$04,$03,$02,$01,$00,$08,$0A,$0C,$06,$07,$78,$A8
LY9:
  .byte $07,$07,$01,$06,$07,$19,$06,$0B,$07,$06,$0B,$13,$06,$0F,$0D,$06,$11,$01,$04,$11,$1B,$04,$01,$1D,$01,$05,$19,$1D,$09,$0F,$15,$07
  .byte $0F,$17,$01,$1D,$05,$09,$0D,$11,$15,$19,$01,$05,$19,$1D,$03,$03,$05,$05,$05,$05,$09,$09,$09,$0D,$0D,$0D,$0F,$0F,$13,$13,$13,$13
  .byte $13,$13,$15,$15,$15,$15,$10,$0F,$0E,$15,$14,$0C,$09,$0A,$07,$06,$03,$02,$00,$04,$05,$01,$08,$0B,$0D,$17,$16,$13,$12,$11,$78,$A8
LY10:
  .byte $08,$05,$0D,$06,$09,$03,$04,$09,$19,$04,$0B,$09,$06,$0B,$11,$06,$0F,$01,$06,$0F,$19,$06,$11,$0B,$0A,$0D,$0F,$11,$03,$0D,$11,$1B
  .byte $0B,$13,$01,$1D,$0B,$0F,$13,$03,$09,$0D,$11,$15,$1B,$01,$05,$19,$1D,$03,$03,$03,$07,$07,$07,$07,$09,$09,$0D,$0D,$0F,$0F,$0F,$13
  .byte $13,$13,$13,$13,$13,$15,$15,$15,$15,$10,$0F,$0E,$14,$15,$11,$12,$13,$16,$17,$0A,$06,$05,$04,$07,$08,$0D,$0C,$0B,$09,$03,$00,$01
  .byte $02,$78,$A8
LY11:
  .byte $08,$05,$01,$0A,$05,$15,$0A,$0B,$0B,$0A,$0D,$05,$02,$0D,$19,$02,$11,$01,$04,$11,$0B,$0A,$11,$1B,$04,$01,$05,$09,$15,$19,$1D,$07
  .byte $0F,$17,$05,$19,$01,$0D,$11,$1D,$07,$0F,$17,$01,$05,$09,$15,$19,$1D,$03,$03,$03,$03,$03,$03,$09,$09,$09,$0B,$0B,$0F,$0F,$0F,$0F
  .byte $13,$13,$13,$15,$15,$15,$15,$15,$15,$10,$0F,$13,$12,$14,$15,$16,$17,$11,$0D,$0C,$07,$06,$09,$0B,$00,$01,$02,$03,$04,$05,$08,$0A
  .byte $0E,$78,$A8
LY12:
  .byte $07,$05,$0D,$06,$09,$09,$06,$09,$11,$06,$0D,$05,$06,$0D,$15,$06,$11,$01,$06,$11,$19,$06,$07,$0F,$17,$03,$0B,$13,$1B,$07,$0D,$11
  .byte $17,$03,$0D,$11,$1B,$01,$0F,$1D,$01,$05,$09,$15,$19,$1D,$03,$03,$03,$07,$07,$07,$07,$0B,$0B,$0B,$0B,$0F,$0F,$0F,$0F,$13,$13,$13
  .byte $15,$15,$15,$15,$15,$15,$10,$0C,$0D,$09,$08,$07,$03,$04,$05,$06,$02,$01,$00,$0B,$0F,$12,$13,$14,$15,$16,$17,$11,$0E,$0A,$78,$A8
LY13:
  .byte $07,$05,$05,$06,$05,$15,$06,$0B,$01,$0A,$0B,$0D,$06,$0B,$15,$0A,$11,$05,$06,$11,$15,$06,$01,$05,$19,$1D,$01,$1D,$0D,$0F,$11,$0F
  .byte $03,$07,$0B,$13,$17,$1B,$0D,$11,$01,$05,$09,$15,$19,$1D,$03,$03,$03,$03,$07,$07,$09,$09,$09,$0D,$0F,$0F,$0F,$0F,$0F,$0F,$13,$13
  .byte $15,$15,$15,$15,$15,$15,$10,$11,$15,$16,$17,$0F,$0E,$0D,$09,$07,$06,$08,$05,$03,$02,$01,$00,$04,$0A,$0B,$0C,$14,$13,$12,$78,$A8
LY14:
  .byte $07,$07,$01,$02,$07,$1D,$02,$0B,$07,$06,$0B,$13,$06,$0F,$01,$04,$0F,$1B,$04,$11,$0D,$06,$01,$05,$09,$0D,$11,$15,$19,$1D,$0F,$07
  .byte $0B,$13,$17,$01,$1D,$0D,$0F,$11,$03,$1B,$01,$05,$19,$1D,$03,$03,$03,$03,$03,$03,$03,$03,$05,$09,$09,$09,$09,$0D,$0D,$0F,$0F,$0F
  .byte $13,$13,$15,$15,$15,$15,$10,$0F,$11,$0B,$0C,$05,$04,$03,$02,$01,$00,$09,$0A,$08,$06,$07,$0E,$13,$16,$17,$15,$14,$12,$0D,$78,$A8
LY_LO:
  .byte <LY0,<LY1,<LY2,<LY3,<LY4,<LY5,<LY6,<LY7,<LY8,<LY9,<LY10,<LY11,<LY12,<LY13,<LY14
LY_HI:
  .byte >LY0,>LY1,>LY2,>LY3,>LY4,>LY5,>LY6,>LY7,>LY8,>LY9,>LY10,>LY11,>LY12,>LY13,>LY14

; big letters of the title
BIG_TOP:
  .byte $00,$07,$07,$18,$18,$18,$18,$07,$00,$E0,$E0,$18,$18,$00,$00,$E0,$00,$18,$18,$18,$18,$19,$19,$1E,$00,$18,$18,$60,$60,$80,$80,$00
  .byte $00,$18,$18,$18,$18,$06,$06,$01,$00,$18,$18,$18,$18,$60,$60,$80,$00,$07,$07,$18,$18,$18,$18,$18,$00,$E0,$E0,$18,$18,$18,$18,$18
  .byte $00,$18,$18,$18,$18,$18,$18,$18,$00,$18,$18,$18,$18,$18,$18,$18,$00,$07,$07,$01,$01,$01,$01,$01,$00,$E0,$E0,$80,$80,$80,$80,$80
  .byte $00,$1F,$1F,$18,$18,$18,$18,$1F,$00,$E0,$E0,$18,$18,$18,$18,$E0,$00,$1F,$1F,$18,$18,$18,$18,$1F,$00,$F8,$F8,$00,$00,$00,$00,$E0
  .byte $00,$18,$18,$18,$18,$18,$18,$18,$00,$00,$00,$00,$00,$00,$00,$00
BIG_BOT:
  .byte $07,$00,$00,$18,$18,$07,$07,$00,$E0,$18,$18,$18,$18,$E0,$E0,$00,$1E,$19,$19,$18,$18,$18,$18,$00,$00,$80,$80,$60,$60,$18,$18,$00
  .byte $01,$01,$01,$01,$01,$01,$01,$00,$80,$80,$80,$80,$80,$80,$80,$00,$18,$19,$19,$18,$18,$07,$07,$00,$18,$98,$98,$60,$60,$98,$98,$00
  .byte $18,$18,$18,$18,$18,$07,$07,$00,$18,$18,$18,$18,$18,$E0,$E0,$00,$01,$01,$01,$01,$01,$07,$07,$00,$80,$80,$80,$80,$80,$E0,$E0,$00
  .byte $1F,$19,$19,$18,$18,$18,$18,$00,$E0,$80,$80,$60,$60,$18,$18,$00,$1F,$18,$18,$18,$18,$1F,$1F,$00,$E0,$00,$00,$00,$00,$F8,$F8,$00
  .byte $18,$18,$18,$18,$18,$1F,$1F,$00,$00,$00,$00,$00,$00,$F8,$F8,$00
TXT_BIG:
  .byte 3,4,160,161,162,163,164,165,32,32,160,161,166,167,168,169,170,171,172,173,172,173,174,175,176,177,0
  .byte 4,4,192,193,194,195,196,197,32,32,192,193,198,199,200,201,202,203,204,205,204,205,206,207,208,209,0
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
  .byte $2C,$06,$00,$02,$30,$06,$00,$02,$33,$08,$30,$08,$31,$06,$00,$02,$35,$06,$00,$02,$38,$10,$37,$08,$35,$08,$33,$08,$30,$08,$31,$08
  .byte $2E,$08,$30,$08,$2C,$08,$2E,$18,$00,$08,$2C,$06,$00,$02,$30,$06,$00,$02,$33,$08,$38,$08,$37,$08,$35,$08,$33,$08,$31,$08,$30,$08
  .byte $33,$08,$2C,$08,$30,$08,$2E,$08,$2B,$08,$2C,$20,$FF
SG0_1:
  .byte $24,$10,$27,$10,$29,$10,$2C,$10,$29,$10,$27,$10,$25,$10,$27,$10,$24,$10,$27,$10,$24,$10,$25,$10,$27,$10,$20,$10,$25,$10,$22,$10
  .byte $24,$20,$FF
SG0_2:
  .byte $08,$08,$0F,$08,$08,$08,$0F,$08,$0D,$08,$14,$08,$0D,$08,$14,$08,$0D,$08,$14,$08,$08,$08,$0F,$08,$0F,$08,$16,$08,$0F,$08,$16,$08
  .byte $08,$08,$0F,$08,$08,$08,$0F,$08,$0D,$08,$14,$08,$0D,$08,$14,$08,$08,$08,$0F,$08,$11,$08,$18,$08,$0F,$08,$16,$08,$08,$10,$08,$10
  .byte $FF
SG0_3:
  .byte $01,$08,$03,$08,$02,$08,$03,$08,$01,$08,$03,$08,$02,$08,$03,$08,$01,$08,$03,$08,$02,$08,$03,$08,$01,$08,$03,$08,$02,$08,$03,$08
  .byte $01,$08,$03,$08,$02,$08,$03,$08,$01,$08,$03,$08,$02,$08,$03,$08,$01,$08,$03,$08,$02,$08,$03,$08,$01,$08,$03,$08,$04,$10,$FF
SG1_0:
  .byte $33,$06,$30,$06,$2C,$06,$30,$06,$33,$06,$38,$0C,$00,$06,$35,$06,$37,$06,$38,$18,$FF
SG1_1:
  .byte $2C,$12,$30,$12,$00,$06,$31,$0C,$30,$18,$FF
SG1_2:
  .byte $08,$0C,$0F,$0C,$14,$12,$0D,$0C,$08,$18,$FF
SG1_3:
  .byte $01,$0C,$02,$0C,$01,$0C,$03,$06,$02,$0C,$04,$18,$FF
SG2_0:
  .byte $2C,$05,$2E,$05,$30,$05,$33,$05,$38,$0A,$00,$05,$33,$05,$38,$05,$3C,$1E,$FF
SG2_1:
  .byte $24,$14,$27,$0F,$2C,$28,$FF
SG2_2:
  .byte $08,$0A,$0F,$0A,$0C,$0A,$08,$0A,$14,$23,$FF
SG2_3:
  .byte $02,$05,$03,$05,$02,$05,$03,$05,$01,$0A,$03,$05,$02,$05,$04,$23,$FF
SG3_0:
  .byte $2C,$08,$30,$08,$33,$08,$38,$10,$37,$08,$35,$08,$33,$08,$35,$10,$31,$08,$35,$08,$38,$08,$3C,$10,$3A,$08,$37,$08,$33,$08,$38,$28
  .byte $FF
SG3_1:
  .byte $27,$18,$25,$18,$29,$18,$2C,$18,$29,$18,$27,$18,$24,$28,$FF
SG3_2:
  .byte $08,$18,$0D,$18,$0D,$18,$11,$18,$0D,$18,$0F,$18,$08,$28,$FF
SG3_3:
  .byte $01,$18,$02,$18,$01,$18,$02,$18,$01,$18,$02,$18,$04,$28,$FF

; one-shot tone effects: period and volume for every frame
WH_TL:
  .byte $00,$B3,$85,$6A,$58,$4C,$42,$3B,$35,$30,$52,$59,$52,$59,$52,$59,$52,$59,$52,$59,$24,$24,$35,$35,$35,$28,$28,$28,$1E,$1E,$1E,$18
  .byte $18,$18,$18,$18,$50,$50,$50,$3F,$3F,$3F,$35,$35,$35,$28,$28,$28,$20,$20,$20,$1B,$1B,$1B,$2F,$2F,$27,$23,$1F,$1C,$1A,$18,$3C,$3C
  .byte $3C,$2D,$2D,$2D,$24,$24,$24,$24,$24,$24,$2D,$2E,$30,$31,$33,$35,$37,$3A,$3C,$3F,$42,$45,$45,$48,$4B,$4E,$52,$56,$5A,$5E,$63,$69
  .byte $6F,$77,$7F,$88,$93,$A0,$AF,$C1,$D8,$F4,$1A,$4D,$96,$09,$3C,$3C,$3C,$3C,$00,$00,$2F,$2F,$2F,$2F,$00,$00,$28,$28,$28,$28,$00,$00
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$78,$78,$78,$78,$78,$78,$78,$78,$78,$7F,$7F,$7F,$7F,$7F,$7F,$7F,$7F,$7F,$8E,$8E,$8E,$8E,$8E,$8E,$8E,$8E
  .byte $8E,$9F,$9F,$9F,$9F,$9F,$9F,$9F,$9F,$9F,$9F,$9F,$9F,$9F,$9F,$9F,$9F,$9F,$9F,$1A,$1C,$1E,$21,$24,$29,$2E,$34,$1E,$1E,$18,$20,$20
  .byte $50,$50,$50,$50,$3F,$3F,$3F,$3F,$35,$35,$35,$28,$28,$28,$28,$28,$28,$28,$28
WH_TH:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$01,$01,$02,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
WH_VOL:
  .byte $00,$0B,$0A,$0A,$09,$08,$07,$07,$06,$05,$06,$06,$06,$06,$05,$05,$05,$05,$04,$04,$0C,$0A,$0A,$08,$05,$0D,$0C,$0A,$0D,$0C,$0A,$0C
  .byte $0A,$08,$06,$04,$0D,$0B,$09,$0D,$0B,$09,$0D,$0B,$09,$0D,$0B,$09,$0D,$0B,$09,$0D,$0B,$09,$0D,$0B,$0C,$0B,$09,$08,$06,$05,$0C,$0B
  .byte $09,$0C,$0B,$09,$0C,$0A,$09,$07,$06,$04,$0D,$0D,$0C,$0C,$0C,$0C,$0B,$0B,$0B,$0B,$0A,$0A,$0B,$0B,$0A,$0A,$09,$09,$09,$08,$08,$07
  .byte $07,$07,$06,$06,$06,$05,$05,$04,$04,$04,$03,$03,$02,$02,$0D,$0C,$0A,$09,$00,$00,$0D,$0C,$0A,$09,$00,$00,$0D,$0C,$0A,$09,$00,$00
  .byte $0D,$0B,$09,$08,$06,$04,$0C,$0B,$0B,$0A,$09,$08,$08,$07,$06,$0C,$0B,$0B,$0A,$09,$08,$08,$07,$06,$0C,$0B,$0B,$0A,$09,$08,$08,$07
  .byte $06,$0C,$0C,$0B,$0B,$0B,$0A,$0A,$0A,$09,$09,$08,$08,$08,$07,$07,$07,$06,$06,$06,$05,$05,$04,$04,$03,$03,$02,$0A,$06,$0A,$08,$05
  .byte $0C,$0B,$0A,$09,$0C,$0B,$0A,$09,$0C,$0B,$09,$0D,$0C,$0A,$09,$07,$06,$04,$03
WH_START:
  .byte $00,$01,$0A,$14,$19,$24,$36,$3E,$4A,$6E,$86,$B3,$BB,$BD,$C0
WH_LEN:
  .byte $00,$09,$0A,$05,$0B,$12,$08,$0C,$24,$18,$2D,$08,$02,$03,$13
W_JUMP = 1
W_GLIDE = 2
W_ACORN = 3
W_LIT = 4
W_GOLD = 5
W_NUT = 6
W_LEAF = 7
W_DIE = 8
W_EXTRA = 9
W_OVER = 10
W_SPAWN = 11
W_TICK = 12
W_KEY = 13
W_SIGN = 14

; noise effects: noise volume / period, low tone volume / period for every frame
EX_NV:
  .byte $00,$0C,$0A,$08,$06,$04,$02,$00,$00,$0D,$0D,$0C,$0C,$0B,$0B,$0A,$0A,$09,$09,$08,$08,$07,$07,$06,$06,$05,$05,$04,$04
EX_NP:
  .byte $00,$02,$03,$04,$05,$06,$07,$08,$09,$06,$06,$06,$06,$07,$07,$07,$07,$08,$08,$08,$08,$09,$09,$09,$09,$0A,$0A,$0A,$0A
EX_VC:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$0B,$0B,$0A,$0A,$09,$09,$08,$08,$07,$07,$06,$06,$05,$05,$04,$04,$03,$03,$02,$02
EX_TL:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$B6,$38,$B6,$38,$B6,$38,$B6,$38,$B6,$38,$B6,$38,$B6,$38,$B6,$38,$B6,$38,$B6,$38
EX_TH:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02
EX_START:
  .byte $00,$01,$09
EX_LEN:
  .byte $00,$08,$14
S_POP = 1
S_BIG = 2

GFX_LOAD:
  .byte 1, $00,$41, <512,>512, <FONT,>FONT
  .byte 2, $00,$61, <512,>512, $F1,0
  .byte 1, $00,$45, <144,>144, <BIG_TOP,>BIG_TOP
  .byte 1, $00,$46, <144,>144, <BIG_BOT,>BIG_BOT
  .byte 2, $00,$65, <144,>144, $91,0
  .byte 2, $00,$66, <144,>144, $A1,0
  .byte 1, $00,$43, <128,>128, <TILEP,>TILEP
  .byte 1, $00,$63, <128,>128, <TILEC,>TILEC
  .byte 2, $00,$60, <8,>8, $11,0
  .byte 1, $00,$49, <512,>512, <FONT,>FONT
  .byte 2, $00,$69, <512,>512, $F1,0
  .byte 1, $00,$4D, <144,>144, <BIG_TOP,>BIG_TOP
  .byte 1, $00,$4E, <144,>144, <BIG_BOT,>BIG_BOT
  .byte 2, $00,$6D, <144,>144, $91,0
  .byte 2, $00,$6E, <144,>144, $A1,0
  .byte 1, $00,$4B, <128,>128, <TILEP,>TILEP
  .byte 1, $00,$6B, <128,>128, <TILEC,>TILEC
  .byte 2, $00,$68, <8,>8, $11,0
  .byte 1, $00,$51, <512,>512, <FONT,>FONT
  .byte 2, $00,$71, <512,>512, $F1,0
  .byte 1, $00,$55, <144,>144, <BIG_TOP,>BIG_TOP
  .byte 1, $00,$56, <144,>144, <BIG_BOT,>BIG_BOT
  .byte 2, $00,$75, <144,>144, $91,0
  .byte 2, $00,$76, <144,>144, $A1,0
  .byte 1, $00,$53, <128,>128, <TILEP,>TILEP
  .byte 1, $00,$73, <128,>128, <TILEC,>TILEC
  .byte 2, $00,$70, <8,>8, $11,0
  .byte 2, $00,$78, <768,>768, $20,0
  .byte 0
