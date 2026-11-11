;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;                                                              ;
;   HAUNTED KEEP  -  an original maze shooter                  ;
;   65C02 assembly, TMS9918A Graphics II (tiles + sprites)     ;
;                                                              ;
;   - Sir Bram the knight walks the halls of a haunted castle  ;
;     (8 x 8 halls, every one with its own walls): out of a    ;
;     door to the next hall, the door behind him is barred     ;
;   - hold a button and push a direction: an arrow in one of   ;
;     8 directions (he stands still to shoot)                  ;
;   - the suits of armor walk to him; they break on the walls, ;
;     on each other and under the arrows; from the third hall  ;
;     on they throw axes, more and faster hall after hall      ;
;   - the walls are cursed: touching them takes a life         ;
;   - a ghost comes in if he lingers: it flies through the     ;
;     walls; an arrow sends it away for a while                ;
;   - every armor broken in a hall: a bonus; 3 lives, one more ;
;     every 5000 points; 1 or 2 players taking turns           ;
;   - records: the 8 best scores, signed with 3 initials, kept ;
;     on the SD with the BIOS KEYB/SD (zone 52 of the save     ;
;     area, lib_records.asm)                                   ;
;   - SOUND (2 x AY-3-8910, played from the NMI at 60 Hz):     ;
;     an organ tune at the title, arrows, axes, the clank of   ;
;     the armors, the wail of the ghost                        ;
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
XLIF        = $3D      ; 2 bytes: lives given for the points (one every 5000)
ROOMI       = $40      ; ---- block of the player, saved: the hall (row * 8 + column)
ROOMS       = $41      ;   halls entered (0-250)
ENTRY       = $42      ;   the door he came in from: 0 left, 1 right, 2 top, 3 bottom
PBLOCK      = 3
GSTATE      = $50      ; 0 playing, 1 a life lost
GT          = $51      ; timer of GSTATE
HUDD        = $52      ; to draw again: 1 score, 2 lives and hall
FIRSTT      = $53      ; 1 = first turn of the game
HX          = $54      ; Sir Bram: left x, top y in the hall (pixels; screen y = HY + 8)
HY          = $55
HFACE       = $56      ; 0 right, 1 left
HPOSE       = $57      ; 0 walking, 1 shooting
HDIR        = $58      ; the way he shoots (0-7: right, up-right, up ... down-right)
HCOOL       = $59      ; frames before the next arrow
HSTEP       = $5A      ; pixels walked (the legs)
LVI         = $5B      ; danger of the hall (0-15)
SIGN        = $5C      ; 1 = the sign of the hall at its start
EXITF       = $5D      ; the door he went out of + 1 (0 = still in the hall)
WALLF       = $5E      ; frames of the flash of the walls
SPRROT      = $5F      ; sprite order (more than 4 on a line take turns)
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
NARM        = $72      ; armors in the hall at its start
ALIVE       = $73      ; armors still standing
LOSTN       = $74      ; lives lost (tests)
DEATHS      = $75      ; what took the last life (tests): 1 a wall, 2 an armor, 3 an axe, 4 the ghost
GOD         = $76      ; tests: 1 = nothing does harm (0 in the game)
BONUSD      = $77      ; 1 = the bonus of the hall is given
WALLC       = $78      ; colour of the walls of this wing
TICKS       = $79      ; frames in the hall
ARRN        = $7A      ; arrows at a time (1-2)
AXMAX       = $7B      ; axes in the air at most
AXP         = $7C      ; chance of a throw in a frame (/256)
AXSF        = $7D      ; speed of the axes: 1 pixel + this fraction a frame
ASPD        = $7E      ; speed of the armors (fraction of a pixel a frame)
ASMART      = $7F      ; chance an armor keeps off a wall (/256)
P_JOY       = $80      ; 2 bytes (joystick, 1 = pressed)
PTS_L       = $82      ; points to add (BCD)
PTS_M       = $83
PTS_H       = $84
SATB        = $85      ; bytes of the SAT to copy
HOFF        = $86      ; name table of NT_XY and CLEAR_NT (always 0 here)
JOYC        = $87      ; both joysticks drive the player playing
GHST        = $88      ; the ghost: 0 not yet, 1 in the hall, 2 sent away
GHX         = $89      ; left x, top y
GHY         = $8A
GHT         = $8B      ; 2 bytes: frames before it comes (back)
GHS         = $8D      ; speed (1/128 of a pixel a frame)
GHACC       = $8E
GWAIL       = $8F      ; frames before the next wail
KILLS       = $90      ; armors broken (tests)
GHITS       = $91      ; ghost sent away (tests)
AXN         = $92      ; axes thrown (tests)
CLANKT      = $93      ; frames before the next clank of the armors
ADX         = $94      ; |distance| from Sir Bram and the way to him (actor being moved)
ADY         = $95
ASX         = $96      ; +1 / $FF
ASY         = $97
Q0          = $98      ; temporaries of the cells
Q1          = $99
Q2          = $9A
Q3          = $9B
CPTR        = $9C      ; 2 bytes: row of the map
NAXE        = $9E      ; axes in the air
AI          = $9F      ; the armor being moved

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

; ---------------- the armors (8 at most) ----------------
NA         = 8
AMX        = $0200       ; left x, top y (pixels)
AMY        = $0208
AMS        = $0210       ; state: 0 none, 1 walking, 2 falling apart
AMT        = $0218       ; steps (the legs) / frames left falling apart
AMACC      = $0220       ; fraction of the speed
; ---------------- the arrows (2 at most) ----------------
NR         = 2
RX         = $0230       ; centre
RY         = $0232
RD         = $0234       ; way (0-7)
RON        = $0236       ; 1 = flying
; ---------------- the axes (3 at most) ----------------
NX         = 3
XX         = $0240       ; centre
XY         = $0243
XD         = $0246       ; way (0-7)
XON        = $0249       ; 1 = flying
XACC       = $024C       ; fraction of the speed
XO         = $024F       ; the armor that threw it
XA         = $0252       ; turn of the blade
; ---------------- the halls where an armor can stand ----------------
BAYL       = $0260       ; 12 bays of the hall: free for an armor
BAYN       = $026C

; ---------------- other RAM ----------------
SAT_BUFFER = $0600       ; 32 sprites x 4 + end of list
PSAVE      = $0690       ; 2 x 16: block of every player
MAP        = $0800       ; 22 rows x 32 cells

; ---------------- parameters ----------------
BTN_MASK    = %00110000
COOL_T      = 14         ; frames between two arrows
START_ROOM  = 56         ; the hall at the bottom left
DIE_T       = 100        ; frames of a life lost

; ---------------- records on the SD (lib_records.asm) ----------------
REC_ZONE    = 52         ; fixed zone of the game in the save area
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
  STZ GOD
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
;  TITLE: the name, the buttons, the points
; ===============================================================
TITLE:
  LDX #$FF
  TXS
  JSR HIDE_SPRITES
  LDA #CMD_GAME
  STA SND_CMD
  JSR VDP_INT_OFF
  JSR CLEAR_NT
  LDA #$E1                     ; the big letters in grey stone
  JSR SET_WALLCOL
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

; one frame of the title: the sprites move;
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
  LDX #0                       ; the second frame of every sprite in turn
  LDY #0
.tf_s:
  LDA TITLE_SN,X
  STA T0
  LDA FRAME_CNT
  AND #16
  BEQ .tf_n
  LDA T0
  CLC
  ADC TITLE_SA,X
  STA T0
.tf_n:
  LDA T0
  STA SAT_BUFFER+2,Y
  INY
  INY
  INY
  INY
  INX
  CPX #TITLE_NS
  BNE .tf_s
.tf_e:
  JMP VDP_INT_ON


; ===============================================================
;  NEW GAME: the first hall, 3 lives for every player
; ===============================================================
NEW_GAME:
  LDX #$01
.ng_p:
  STZ SCL,X
  STZ SCM,X
  STZ SCH,X
  STZ LIVES,X
  STZ XLIF,X
  DEX
  BPL .ng_p
  STZ LOSTN
  STZ KILLS
  STZ GHITS
  STZ AXN
  LDA NPL
  STA CURP
.ng_w:
  DEC CURP                     ; player NPL-1 ... 0
  LDX CURP
  LDA #3
  STA LIVES,X
  LDA #START_ROOM
  STA ROOMI
  STZ ROOMS
  STZ ENTRY
  JSR SAVE_PLAYER
  LDA CURP
  BNE .ng_w
  LDA #$01
  STA FIRSTT
  ; fall into TURN_START with CURP = 0

; ===============================================================
;  TURN OF A PLAYER: his hall, from the door he came in from
; ===============================================================
TURN_START:
  LDX CURP
  JSR LOAD_PLAYER
  LDA #1
  STA SIGN

ROOM_START:
  LDX #$FF
  TXS
  JSR HIDE_SPRITES
  JSR VDP_INT_OFF
  LDA #$82                     ; display off while the hall is drawn
  STA VREG
  LDA #(VDP_REGISTER_BITS | 1)
  STA VREG
  JSR SET_ROOM                 ; the map, Sir Bram and the armors at their places
  JSR CLEAR_NT
  JSR DRAW_LEVEL
  LDA WALLC
  JSR SET_WALLCOL
  JSR DRAW_HUD
  STZ HUDD
  STZ GSTATE
  LDA SIGN
  BEQ .rs_ns
  JSR MSG_ROOM
.rs_ns:
  JSR BUILD_SAT
  JSR VDP_INT_ON               ; (display on)
  LDA SIGN
  BEQ .rs_go
  STZ SIGN
  LDA FIRSTT                   ; the tune at the first turn
  BEQ .rs_short
  STZ FIRSTT
  LDA #1
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
  BRA .rs_w
.rs_short:
  LDA #90
  JSR WAIT_FRAMES
.rs_w:
  LDA #10
  JSR WAIT_FRAMES
  JSR VDP_INT_OFF
  JSR MSG_CLEAR
  JSR VDP_INT_ON
  LDA #CMD_GAME
  STA SND_CMD
  LDA #1
  JSR WAIT_FRAMES
  BRA .rs_g
.rs_go:
  LDA #6
  JSR WAIT_FRAMES
.rs_g:
  LDA #W_GRATE                 ; the door behind him is barred
  LDX #2
  JSR SFX_WHISTLE
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
  INC TICKS
  JSR WALL_FLASH
  LDA GSTATE
  BNE .gl_ns
  JSR HERO
  JSR ARROWS
  JSR ARMORS
  JSR AXES
  JSR GHOST
  JSR HITS
.gl_ns:
  JSR UPDATE_HUD
  JSR BUILD_SAT
WEND:
  JSR VDP_INT_ON
  LDA EXITF
  BNE ROOM_EXIT
  LDA GSTATE
  BEQ GAME_LOOP
  DEC GT
  BNE GAME_LOOP
  JMP LOSE_LIFE


; ===============================================================
;  OUT OF A DOOR: the next hall (the castle wraps round)
; ===============================================================
ROOM_EXIT:
  JSR HIDE_SPRITES
  LDA ROOMI
  AND #7
  STA T0                       ; column
  LDA ROOMI
  LSR A
  LSR A
  LSR A
  STA T1                       ; row
  LDX EXITF
  DEX                          ; 0 left, 1 right, 2 top, 3 bottom
  TXA
  EOR #1                       ; he comes in from the other side
  STA ENTRY
  CPX #0
  BNE .re_r
  DEC T0
  BRA .re_s
.re_r:
  CPX #1
  BNE .re_t
  INC T0
  BRA .re_s
.re_t:
  CPX #2
  BNE .re_b
  DEC T1
  BRA .re_s
.re_b:
  INC T1
.re_s:
  LDA T1
  AND #7
  ASL A
  ASL A
  ASL A
  STA T1
  LDA T0
  AND #7
  ORA T1
  STA ROOMI
  LDA ROOMS
  CMP #250
  BCS .re_n
  INC ROOMS
.re_n:
  JSR SAVE_PLAYER
  JMP ROOM_START

LOSE_LIFE:
  INC LOSTN
  LDX CURP
  DEC LIVES,X
  JSR SAVE_PLAYER
  LDA #20
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
  LDA #1                       ; the same player: the hall from the start
  STA SIGN
  JMP ROOM_START

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
  LDA #$20
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
  TXA                          ; extra byte: the halls entered
  ASL A
  ASL A
  ASL A
  ASL A
  TAY
  LDA PSAVE+1,Y
  INC A
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
REC_NAME:  .byte "HAUNTED KEEP    "
REC_HEAD:  .byte "BRAVEST KNIGHTS",0
REC_XLBL:  .byte "HALL ",0


; ===============================================================
;  HUD: row 0 (scores), row 23 (lives, hall)
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

; row 23: the spare lives (cols 0-7), HALL nn (22-28), the player (31)
DRAW_STATUS:
  LDX #23
  LDY #0
  JSR NT_XY
  LDX CURP                     ; the spare lives (at most 8)
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
  CPY #20
  BNE .ds_i
  LDX #23
  LDY #22
  JSR NT_XY
  LDX #0
.ds_l:
  LDA TXT_HALLH,X
  STA VDATA
  INX
  CPX #5
  BNE .ds_l
  LDA ROOMS                    ; the halls entered (99 at most on the screen)
  INC A
  CMP #100
  BCC .ds_n
  LDA #99
.ds_n:
  JSR PUT_NUM
  LDA #$20
  STA VDATA
  STA VDATA
  LDA NPL                      ; the player at the right end with 2 players
  CMP #2
  BNE .ds_e
  LDX #23
  LDY #31
  JSR NT_XY
  LDA CURP
  CLC
  ADC #$31
  STA VDATA
.ds_e:
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

UPDATE_HUD:                    ; HUDD bits: 1 score, 2 lives and hall, 4 the bonus
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
  BEQ .uh_b
  JSR DRAW_STATUS
.uh_b:
  PLA
  AND #4
  BEQ .uh_r
  JMP DRAW_BONUS
.uh_r:
  RTS

; row 23, cols 10-19: BONUS nn0
DRAW_BONUS:
  LDX #23
  LDY #10
  JSR NT_XY
  LDX #0
.db_l:
  LDA TXT_BONUS,X
  STA VDATA
  INX
  CPX #6
  BNE .db_l
  LDA NARM
  JSR PUT_NUM
  LDA #$30
  STA VDATA
  RTS


; ===============================================================
;  PLAYERS AND SCORE
; ===============================================================
SAVE_PLAYER:                   ; player CURP: his block
  LDA CURP
  ASL A
  ASL A
  ASL A
  ASL A
  TAX
  LDY #0
.sp_b:
  LDA ROOMI,Y
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
  STA ROOMI,Y
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

; PTS_L / PTS_M / PTS_H (BCD) to the player playing; a life more every 5000
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
  LDA #1
  TSB HUDD
  LDA SCH,X                    ; fives of thousands = SCH.hi * 20 + SCH.lo * 2 + SCM.hi / 5
  LSR A
  LSR A
  LSR A
  LSR A
  STA T0
  ASL A
  ASL A
  CLC
  ADC T0                       ; * 5
  ASL A
  ASL A                        ; * 20
  STA T0
  LDA SCH,X
  AND #$0F
  ASL A
  CLC
  ADC T0
  STA T0
  LDA SCM,X
  LSR A
  LSR A
  LSR A
  LSR A
  CMP #5
  BCC .as_f
  INC T0
.as_f:
  LDA T0
  CMP XLIF,X
  BEQ .as_r
  BCC .as_r
  INC XLIF,X
  LDA LIVES,X
  CMP #9
  BCS .as_r
  INC LIVES,X
  LDA #2
  TSB HUDD
  LDA #W_EXTRA
  LDX #2
  JSR SFX_WHISTLE
.as_r:
  PLY
  PLX
  RTS


; ===============================================================
;  THE HALL: map, drawing, signs
; ===============================================================
HWC0        = $A0      ; HITWALL: the two columns and the three rows to look at
HWC1        = $A1
HWR0        = $A2
HWR1        = $A3
HWR2        = $A4
AXIS        = $A5      ; armor step: 0 along x, 1 along y
NX0         = $A6      ; armor step: the new place
NY0         = $A7
STEPS       = $A8      ; pixels to move in this frame
PILB        = $A9      ; the pillars of the hall (bay + 1 in each nibble)

; the hall ROOMI with the danger of ROOMS: the tables, the map, Sir Bram, the armors, the ghost
SET_ROOM:
  LDA ROOMS
  CMP #15
  BCC .sr_l
  LDA #15
.sr_l:
  STA LVI
  TAX
  LDA NARM_T,X
  STA NARM
  LDA AXMAX_T,X
  STA AXMAX
  LDA AXP_T,X
  STA AXP
  LDA AXSF_T,X
  STA AXSF
  LDA ASPD_T,X
  STA ASPD
  LDA SMART_T,X
  STA ASMART
  LDA ARRN_T,X
  STA ARRN
  LDA GTIME_T,X                ; the ghost: GTIME * 4 frames
  STA GHT
  STZ GHT+1
  ASL GHT
  ROL GHT+1
  ASL GHT
  ROL GHT+1
  STZ GHST
  LDA #40
  STA GHS
  STZ GHACC
  STZ GWAIL
  LDA ROOMI                    ; the colour of the wing (two rows of halls each)
  LSR A
  LSR A
  LSR A
  LSR A
  TAX
  LDA WING_COL,X
  STA WALLC
  JSR BUILD_MAP
  LDX ENTRY                    ; Sir Bram at the door he came in from
  LDA ENT_X,X
  STA HX
  LDA ENT_Y,X
  STA HY
  STZ HFACE
  CPX #1
  BNE .sr_f
  INC HFACE
.sr_f:
  STZ HPOSE
  STZ HCOOL
  STZ HSTEP
  LDX #NR-1
.sr_r:
  STZ RON,X
  DEX
  BPL .sr_r
  LDX #NX-1
.sr_x:
  STZ XON,X
  DEX
  BPL .sr_x
  STZ NAXE
  STZ TICKS
  STZ EXITF
  STZ WALLF
  STZ BONUSD
  LDA #20
  STA CLANKT
  JMP SPAWN

; the map of the hall: outer walls with 4 doors, the 6 posts, the walls of the hall, torches, pillars, the grate
BUILD_MAP:
  LDA #<MAP                    ; all floor
  STA PTR
  LDA #>MAP
  STA PTR+1
  LDX #3
  LDY #0
  TYA
.bm_z:
  STA (PTR),Y
  INY
  BNE .bm_z
  INC PTR+1
  DEX
  BNE .bm_z
  LDX #31                      ; rows 0 and 21
.bm_h:
  LDY #0
  LDA #1
  JSR MSET
  LDY #21
  JSR MSET
  DEX
  BPL .bm_h
  LDY #21                      ; columns 0 and 31
.bm_v:
  LDX #0
  LDA #1
  JSR MSET
  LDX #31
  JSR MSET
  DEY
  BPL .bm_v
  LDA #0                       ; the 4 doors
  JSR DOORS
  LDX #5                       ; the posts
.bm_p:
  PHX
  LDA POST_C,X
  LDY POST_R,X
  TAX
  LDA #1
  JSR MSET
  PLX
  DEX
  BPL .bm_p
  LDA ROOMI                    ; the walls of this hall: 17 bits
  STZ PTR+1
  ASL A
  ROL PTR+1
  ASL A
  ROL PTR+1
  CLC
  ADC #<ROOM_D
  STA PTR
  LDA PTR+1
  ADC #>ROOM_D
  STA PTR+1
  LDY #0
  LDA (PTR),Y
  STA Q0
  INY
  LDA (PTR),Y
  STA Q1
  INY
  LDA (PTR),Y
  STA Q2
  INY
  LDA (PTR),Y
  STA PILB                     ; the pillars
  LDX #0
.bm_s:
  LSR Q2
  ROR Q1
  ROR Q0
  BCC .bm_sn
  JSR SEGMENT
.bm_sn:
  INX
  CPX #NSEG
  BNE .bm_s
  LDX #7                       ; the torches
.bm_t:
  PHX
  LDA TORCH_C,X
  LDY TORCH_R,X
  TAX
  LDA #7
  JSR MSET
  PLX
  DEX
  BPL .bm_t
  LDA PILB                     ; two pillars at most (bay + 1 in each nibble)
  AND #$0F
  JSR PILLAR
  LDA PILB
  LSR A
  LSR A
  LSR A
  LSR A
  JSR PILLAR
  LDA #2                       ; the grate on the door he came in from
  LDX ENTRY
  JMP DOOR1

; A = bay + 1 (0 = none): a pillar of 2 x 2 cells in the middle of the bay
PILLAR:
  BEQ .pl_r
  DEC A
  TAY
  LDA PIL_C,Y
  TAX
  LDA PIL_R,Y
  TAY
  LDA #3
  JSR MSET
  INX
  LDA #4
  JSR MSET
  INY
  LDA #6
  JSR MSET
  DEX
  LDA #5
  JSR MSET
.pl_r:
  RTS

; X = segment (keeps X): a line of wall
SEGMENT:
  PHX
  LDA SEG_N,X
  STA T2
  LDA SEG_H,X
  STA T3
  LDA SEG_C,X
  LDY SEG_R,X
  TAX
.sg_l:
  LDA #1
  JSR MSET
  LDA T3
  BEQ .sg_v
  INX
  BRA .sg_n
.sg_v:
  INY
.sg_n:
  DEC T2
  BNE .sg_l
  PLX
  RTS

; A = cell: all the 4 doors
DOORS:
  LDX #3
.do_l:
  PHX
  PHA
  JSR DOOR1
  PLA
  PLX
  DEX
  BPL .do_l
  RTS

; A = cell, X = door (0 left, 1 right, 2 top, 3 bottom): its 4 cells
DOOR1:
  STA T4
  LDA DOOR_C,X
  STA T2
  LDA DOOR_R,X
  STA T3
  CPX #2
  LDA #0                       ; (C stays) 1 = the cells go along the row
  ROL A
  STA T5
  LDX T2
  LDY T3
  LDA #4
  STA T2
.d1_l:
  LDA T4
  JSR MSET
  LDA T5
  BEQ .d1_v
  INX
  BRA .d1_n
.d1_v:
  INY
.d1_n:
  DEC T2
  BNE .d1_l
  RTS

; X = column, Y = row, A = cell: into the map only (keeps A, X, Y)
MSET:
  PHA
  LDA MR_LO,Y
  STA CPTR
  LDA MR_HI,Y
  STA CPTR+1
  STY T6
  TXA
  TAY
  PLA
  STA (CPTR),Y
  LDY T6
  RTS

; the armors: one in a bay at random, never in the bay by the door nor in a bay with a pillar
SPAWN:
  STZ BAYN
  LDX #0
.sp_b:
  LDY ENTRY                    ; the bays near the door are left empty
  TXA
  CMP EXCL_A,Y
  BEQ .sp_n
  CMP EXCL_B,Y
  BEQ .sp_n
  LDA PILB                     ; and the bays with a pillar
  AND #$0F
  STA T0
  TXA
  INC A
  CMP T0
  BEQ .sp_n
  LDA PILB
  LSR A
  LSR A
  LSR A
  LSR A
  STA T0
  TXA
  INC A
  CMP T0
  BEQ .sp_n
  TXA
  LDY BAYN
  STA BAYL,Y
  INC BAYN
.sp_n:
  INX
  CPX #12
  BNE .sp_b
  LDX #NA-1
.sp_o:
  STZ AMS,X
  DEX
  BPL .sp_o
  LDA NARM                     ; as many as there are bays
  CMP BAYN
  BCC .sp_k
  LDA BAYN
.sp_k:
  STA NARM
  STA ALIVE
  LDX #0
.sp_a:
  CPX NARM
  BEQ .sp_e
  JSR NEXT_RND                 ; a bay left at random
.sp_m:
  CMP BAYN
  BCC .sp_t
  SEC
  SBC BAYN
  BRA .sp_m
.sp_t:
  TAY
  LDA BAYL,Y
  STA T0                       ; the bay
  PHY
  LDY BAYN                     ; the last bay takes its place
  DEY
  STY BAYN
  LDA BAYL,Y
  PLY
  STA BAYL,Y
  LDY T0
  JSR NEXT_RND
  AND #7
  SEC
  SBC #12
  CLC
  ADC BAY_CX,Y
  STA AMX,X
  JSR NEXT_RND
  AND #7
  SEC
  SBC #12
  CLC
  ADC BAY_CY,Y
  STA AMY,X
  LDA #1
  STA AMS,X
  STZ AMT,X
  JSR NEXT_RND
  STA AMACC,X
  INX
  BRA .sp_a
.sp_e:
  RTS

DRAW_LEVEL:
  LDY #0
.dl_r:
  PHY
  JSR DRAW_ROW
  PLY
  INY
  CPY #22
  BNE .dl_r
  RTS

; Y = row of the hall (0-21): its 32 tiles on the screen row Y + 1
DRAW_ROW:
  STY T3
  TYA
  TAX
  INX
  LDY #0
  JSR NT_XY
  LDY T3
  LDA MR_LO,Y
  STA CPTR
  LDA MR_HI,Y
  STA CPTR+1
  LDY #0
.dr_c:
  LDA (CPTR),Y
  TAX
  LDA TILE_OF,X
  STA T5
  LDA VAR_OF,X
  BEQ .dr_p
  TYA
  EOR T3
  AND #1
  CLC
  ADC T5
  STA T5
.dr_p:
  LDA T5
  STA VDATA
  INY
  CPY #32
  BNE .dr_c
  RTS

; X = column, Y = row: A = the cell (wall outside the hall); keeps X and Y
; (the flags do not follow A: compare it)
GETC:
  CPX #32
  BCS .gc_s
  CPY #22
  BCS .gc_s
  LDA MR_LO,Y
  STA CPTR
  LDA MR_HI,Y
  STA CPTR+1
  PHY
  TXA
  TAY
  LDA (CPTR),Y
  PLY
  RTS
.gc_s:
  LDA #1
  RTS

; Q0 = left x, Q1 = top y, Q2 = width - 1, Q3 = height - 1 (pixels of the hall):
; C = 1 if a corner or the middle of a side is on a wall
HITWALL:
  LDA Q0
  LSR A
  LSR A
  LSR A
  STA HWC0
  LDA Q0
  CLC
  ADC Q2
  LSR A
  LSR A
  LSR A
  STA HWC1
  LDA Q1
  LSR A
  LSR A
  LSR A
  STA HWR0
  LDA Q3
  LSR A
  CLC
  ADC Q1
  LSR A
  LSR A
  LSR A
  STA HWR1
  LDA Q1
  CLC
  ADC Q3
  LSR A
  LSR A
  LSR A
  STA HWR2
  LDY HWR0
  JSR .hw_r1
  BCS .hw_x
  LDY HWR1
  JSR .hw_r1
  BCS .hw_x
  LDY HWR2
.hw_r1:                        ; Y = row: the two columns
  CPY #22
  BCS .hw_x
  LDA MR_LO,Y
  STA CPTR
  LDA MR_HI,Y
  STA CPTR+1
  LDY HWC0
  LDA (CPTR),Y
  BNE .hw_y
  LDY HWC1
  LDA (CPTR),Y
  BNE .hw_y
  CLC
.hw_x:
  RTS
.hw_y:
  SEC
  RTS

; A = colour byte: the two wall tiles in the three thirds (VDP interrupt off)
SET_WALLCOL:
  STA T4
  LDX #0
.wc_t:
  LDA WC_LO,X
  STA VREG
  LDA WC_HI,X
  STA VREG
  LDY #16
  LDA T4
.wc_b:
  STA VDATA
  DEY
  BNE .wc_b
  INX
  CPX #3
  BNE .wc_t
  RTS

; the walls flash after Sir Bram touched them
WALL_FLASH:
  LDA WALLF
  BEQ .wf_r
  DEC WALLF
  BEQ .wf_e
  AND #3
  BNE .wf_r
  LDA WALLF
  AND #4
  BEQ .wf_b
  LDA #$F5
  JMP SET_WALLCOL
.wf_b:
  LDA #$5F
  JMP SET_WALLCOL
.wf_e:
  LDA WALLC
  JMP SET_WALLCOL
.wf_r:
  RTS

; the sign of the hall on rows 9-13: HALL nn, SIR BRAM or PLAYER n
MSG_ROOM:
  LDA #<TXT_SIGN
  STA TP
  LDA #>TXT_SIGN
  STA TP+1
  JSR PRINT
  LDX #10
  LDY #13
  JSR NT_XY
  LDX #0
.mr_l:
  LDA TXT_HALLH,X
  STA VDATA
  INX
  CPX #5
  BNE .mr_l
  LDA ROOMS
  INC A
  CMP #100
  BCC .mr_n
  LDA #99
.mr_n:
  JSR PUT_NUM
  LDX #12
  LDY #12
  JSR NT_XY
  LDA NPL
  CMP #2
  BEQ .mr_p
  LDX #0
.mr_s:
  LDA TXT_SIR,X
  STA VDATA
  INX
  CPX #8
  BNE .mr_s
  RTS
.mr_p:
  LDX #0
.mr_q:
  LDA TXT_PLAYERH,X
  STA VDATA
  INX
  CPX #7
  BNE .mr_q
  LDA CURP
  CLC
  ADC #$31
  STA VDATA
  RTS

MSG_CLEAR:                     ; the hall again on rows 9-13
  LDY #8
.mc_r:
  PHY
  JSR DRAW_ROW
  PLY
  INY
  CPY #13
  BNE .mc_r
  RTS


; ===============================================================
;  SIR BRAM
; ===============================================================
HERO:
  LDA HCOOL
  BEQ .h_c
  DEC HCOOL
.h_c:
  LDA JOYC                     ; a button held: he stands and shoots
  AND #BTN_MASK
  BEQ .h_walk
  LDA #1
  STA HPOSE
  LDA JOYC
  AND #15
  TAX
  LDA JOYDIR,X
  BPL .h_d
  LDA HFACE                    ; no way pushed: where he looks
  ASL A
  ASL A
.h_d:
  STA HDIR
  TAX
  LDA DXT,X                    ; he turns to that side
  BEQ .h_f
  LDY #0
  CMP #1
  BEQ .h_fs
  INY
.h_fs:
  STY HFACE
.h_f:
  LDA HCOOL
  BNE .h_wall
  JSR FIRE
  BRA .h_wall
.h_walk:
  STZ HPOSE
  LDA JOYC
  AND #15
  BEQ .h_wall
  STA T0
  INC HSTEP
  AND #8
  BEQ .h_l
  INC HX
  STZ HFACE
.h_l:
  LDA T0
  AND #4
  BEQ .h_u
  DEC HX
  LDA #1
  STA HFACE
.h_u:
  LDA T0
  AND #1
  BEQ .h_dn
  DEC HY
.h_dn:
  LDA T0
  AND #2
  BEQ .h_wall
  INC HY
.h_wall:
  LDA HX                       ; out of a door?
  CMP #2
  BCS .h_x1
  LDA #1
  BRA .h_out
.h_x1:
  CMP #238
  BCC .h_y0
  LDA #2
  BRA .h_out
.h_y0:
  LDA HY
  CMP #2
  BCS .h_y1
  LDA #3
  BRA .h_out
.h_y1:
  CMP #158
  BCC .h_in
  LDA #4
.h_out:
  STA EXITF
  RTS
.h_in:
  LDA HX                       ; on a cursed wall?
  CLC
  ADC #4
  STA Q0
  LDX HY
  INX
  STX Q1
  LDA #6
  STA Q2
  LDA #14
  STA Q3
  JSR HITWALL
  BCC .h_r
  LDA GOD
  AND #2
  BNE .h_r
  LDA #60
  STA WALLF
  LDA #1
  JMP DIES
.h_r:
  RTS

; an arrow, if one is free, the way HDIR
FIRE:
  LDX #0
.fi_l:
  LDA RON,X
  BEQ .fi_f
  INX
  CPX ARRN
  BNE .fi_l
  RTS
.fi_f:
  LDA #1
  STA RON,X
  LDY HDIR
  TYA
  STA RD,X
  LDA HX
  CLC
  ADC #8
  CLC
  ADC DX6,Y
  STA RX,X
  LDA HY
  CLC
  ADC #8
  CLC
  ADC DY6,Y
  STA RY,X
  LDA #COOL_T
  STA HCOOL
  LDA #W_ARROW
  LDY HX
  JMP WHISTLE_AT

; A = whistle, Y = x on the screen: on that side
WHISTLE_AT:
  LDX #0
  CPY #$80
  BCC .wa_l
  INX
.wa_l:
  JMP SFX_WHISTLE


; ===============================================================
;  THE ARROWS
; ===============================================================
ARROWS:
  LDX #NR-1
.ar_l:
  LDA RON,X
  BEQ .ar_n
  JSR ARROW1
.ar_n:
  DEX
  BPL .ar_l
  RTS

; X = arrow (keeps X)
ARROW1:
  LDY RD,X
  LDA RX,X
  CLC
  ADC DX4,Y
  STA RX,X
  CMP #2
  BCC .a1_off
  CMP #254
  BCS .a1_off
  LDA RY,X
  CLC
  ADC DY4,Y
  STA RY,X
  CMP #2
  BCC .a1_off
  CMP #174
  BCS .a1_off
  PHX                          ; into a wall?
  LDA RY,X
  LSR A
  LSR A
  LSR A
  TAY
  LDA RX,X
  LSR A
  LSR A
  LSR A
  TAX
  JSR GETC
  PLX
  CMP #0
  BEQ .a1_ok
.a1_off:
  STZ RON,X
  RTS
.a1_ok:
  LDA RX,X                     ; an armor?
  STA Q2
  LDA RY,X
  STA Q3
  LDY #NA-1
.a1_a:
  LDA AMS,Y
  CMP #1
  BNE .a1_an
  LDA AMX,Y
  CLC
  ADC #8
  JSR ABS_X
  CMP #7
  BCS .a1_an
  LDA AMY,Y
  CLC
  ADC #8
  JSR ABS_Y
  CMP #8
  BCS .a1_an
  STZ RON,X
  PHX
  TYA
  TAX
  JSR BREAK_ARMOR
  PLX
  RTS
.a1_an:
  DEY
  BPL .a1_a
  LDY #NX-1                    ; an axe?
.a1_x:
  LDA XON,Y
  BEQ .a1_xn
  LDA XX,Y
  JSR ABS_X
  CMP #6
  BCS .a1_xn
  LDA XY,Y
  JSR ABS_Y
  CMP #6
  BCS .a1_xn
  STZ RON,X
  LDA #0
  STA XON,Y
  DEC NAXE
  PHX
  LDA #S_CHINK
  LDY RX,X
  JSR BOOM_AT
  LDA #$20
  LDY #0
  JSR ADD_PTS
  PLX
  RTS
.a1_xn:
  DEY
  BPL .a1_x
  LDA GHST                     ; the ghost?
  CMP #1
  BNE .a1_r
  LDA GHX
  CLC
  ADC #8
  JSR ABS_X
  CMP #8
  BCS .a1_r
  LDA GHY
  CLC
  ADC #8
  JSR ABS_Y
  CMP #9
  BCS .a1_r
  STZ RON,X
  PHX
  JSR GHOST_AWAY
  PLX
  RTS
.a1_r:
  RTS

ABS_X:                         ; A = |A - Q2|
  SEC
  SBC Q2
  BCS .ab_r
  EOR #$FF
  INC A
.ab_r:
  RTS
ABS_Y:                         ; A = |A - Q3|
  SEC
  SBC Q3
  BCS .ay_r
  EOR #$FF
  INC A
.ay_r:
  RTS

; X = armor: it falls apart (50 points); every armor broken = the bonus (keeps X)
BREAK_ARMOR:
  LDA AMS,X
  CMP #1
  BNE .ba_r
  LDA #2
  STA AMS,X
  LDA #24
  STA AMT,X
  DEC ALIVE
  INC KILLS
  PHX
  LDA #S_BREAK
  LDY AMX,X
  JSR BOOM_AT
  LDA #$50
  LDY #0
  JSR ADD_PTS
  PLX
  LDA ALIVE
  BNE .ba_r
  LDA BONUSD
  BNE .ba_r
  INC BONUSD
  LDA NARM                     ; 10 points an armor
  ASL A
  ASL A
  ASL A
  ASL A
  LDY #0
  JSR ADD_PTS
  LDA #4
  TSB HUDD
  PHX
  LDA #W_BONUS
  LDX #2
  JSR SFX_WHISTLE
  PLX
.ba_r:
  RTS


; ===============================================================
;  THE ARMORS
; ===============================================================
ARMORS:
  LDA ALIVE                    ; the clank of their steps
  BEQ .am_go
  DEC CLANKT
  BNE .am_go
  LDA #22
  STA CLANKT
  LDA #W_CLANK
  LDX #2
  JSR SFX_WHISTLE
.am_go:
  LDX #NA-1
.am_l:
  LDA AMS,X
  BEQ .am_n
  CMP #2
  BNE .am_w
  DEC AMT,X                    ; falling apart
  BNE .am_n
  STZ AMS,X
  BRA .am_n
.am_w:
  STX AI
  JSR ARMOR1
  LDX AI
.am_n:
  DEX
  BPL .am_l
  ; ---- two armors that run into each other both fall apart
  LDX #0
.am_p:
  LDA AMS,X
  CMP #1
  BNE .am_pn
  LDA AMX,X
  STA Q2
  LDA AMY,X
  STA Q3
  TXA
  TAY
.am_q:
  INY
  CPY #NA
  BEQ .am_pn
  LDA AMS,Y
  CMP #1
  BNE .am_q
  LDA AMX,Y
  JSR ABS_X
  CMP #12
  BCS .am_q
  LDA AMY,Y
  JSR ABS_Y
  CMP #14
  BCS .am_q
  PHY
  JSR BREAK_ARMOR
  PLA
  PHX
  TAX
  JSR BREAK_ARMOR
  PLX
.am_pn:
  INX
  CPX #NA-1
  BNE .am_p
  RTS

; X = armor (AI): the way to Sir Bram, a throw, a step
ARMOR1:
  LDA HX                       ; |dx| and the way along x
  SEC
  SBC AMX,X
  LDY #1
  BCS .a_x
  EOR #$FF
  INC A
  LDY #$FF
.a_x:
  STA ADX
  STY ASX
  LDA HY
  SEC
  SBC AMY,X
  LDY #1
  BCS .a_y
  EOR #$FF
  INC A
  LDY #$FF
.a_y:
  STA ADY
  STY ASY
  ; ---- a throw, when he is on a line with Sir Bram
  LDA NAXE
  CMP AXMAX
  BCS .a_m
  LDA ADX
  CMP #4
  BCC .a_t
  LDA ADY
  CMP #4
  BCC .a_t
  LDA ADX
  SEC
  SBC ADY
  BCS .a_d
  EOR #$FF
  INC A
.a_d:
  CMP #4
  BCS .a_m
.a_t:
  JSR NEXT_RND
  CMP AXP
  BCS .a_m
  JSR THROW
  LDX AI
  ; ---- a step now and then
.a_m:
  LDA AMACC,X
  CLC
  ADC ASPD
  STA AMACC,X
  BCC .a_r
  LDA ADX                      ; along the shorter way first (to get on a line with him)
  CMP #2
  BCS .a_x2
  LDA ADY
  CMP #2
  BCC .a_r
  LDA #1
  BRA .a_s
.a_x2:
  LDA ADY
  CMP #2
  BCC .a_ax
  LDA ADX
  CMP ADY
  BCC .a_ax
  LDA #1
  BRA .a_s
.a_ax:
  LDA #0
.a_s:
  STA AXIS
  JSR TRY_STEP
  BCC .a_r
  JSR NEXT_RND                 ; a wall ahead: a clever armor keeps off it
  CMP ASMART
  BCS .a_dumb
  LDA AXIS                     ; the other way, if it is not on a line already
  EOR #1
  STA AXIS
  BNE .a_oy
  LDA ADX
  CMP #2
  BCC .a_r
  BRA .a_o
.a_oy:
  LDA ADY
  CMP #2
  BCC .a_r
.a_o:
  JSR TRY_STEP
.a_r:
  RTS
.a_dumb:
  LDA NX0                      ; it walks into the wall and falls apart
  STA AMX,X
  LDA NY0
  STA AMY,X
  JMP BREAK_ARMOR

; X = armor, AXIS: one pixel that way, if there is no wall (C = 1: a wall, NX0 / NY0 = the place)
TRY_STEP:
  LDA AMX,X
  STA NX0
  LDA AMY,X
  STA NY0
  LDA AXIS
  BNE .ts_y
  LDA NX0
  CLC
  ADC ASX
  STA NX0
  BRA .ts_c
.ts_y:
  LDA NY0
  CLC
  ADC ASY
  STA NY0
.ts_c:
  LDA NX0
  CLC
  ADC #4
  STA Q0
  LDA NY0
  INC A
  STA Q1
  LDA #7
  STA Q2
  LDA #14
  STA Q3
  JSR HITWALL
  LDX AI
  BCS .ts_r
  LDA NX0
  STA AMX,X
  LDA NY0
  STA AMY,X
  INC AMT,X
  CLC
.ts_r:
  RTS

; X = armor (AI): an axe at Sir Bram, along the line he is on
THROW:
  LDY #NX-1
.th_f:
  LDA XON,Y
  BEQ .th_k
  DEY
  BPL .th_f
  RTS
.th_k:
  LDA ADX
  CMP #4
  BCS .th_h
  LDA #2                       ; up or down
  LDX ASY
  BMI .th_s
  LDA #6
  BRA .th_s
.th_h:
  LDA ADY
  CMP #4
  BCS .th_g
  LDA #0                       ; right or left
  LDX ASX
  BPL .th_s
  LDA #4
  BRA .th_s
.th_g:
  LDA ASX                      ; a diagonal
  BMI .th_gl
  LDA #1
  LDX ASY
  BMI .th_s
  LDA #7
  BRA .th_s
.th_gl:
  LDA #3
  LDX ASY
  BMI .th_s
  LDA #5
.th_s:
  STA XD,Y
  LDX AI
  TXA
  STA XO,Y
  LDA AMX,X
  CLC
  ADC #8
  STA XX,Y
  LDA AMY,X
  CLC
  ADC #8
  STA XY,Y
  LDA #1
  STA XON,Y
  LDA #0
  STA XACC,Y
  STA XA,Y
  INC NAXE
  INC AXN
  LDA #W_AXE
  LDY AMX,X
  JMP WHISTLE_AT


; ===============================================================
;  THE AXES
; ===============================================================
AXES:
  LDX #NX-1
.ax_l:
  LDA XON,X
  BEQ .ax_n
  JSR AXE1
.ax_n:
  DEX
  BPL .ax_l
  RTS

; X = axe (keeps X)
AXE1:
  INC XA,X
  LDA #1                       ; 1 pixel + the fraction
  STA STEPS
  LDA XACC,X
  CLC
  ADC AXSF
  STA XACC,X
  BCC .x1_m
  INC STEPS
.x1_m:
  LDY XD,X
  LDA XX,X
  CLC
  ADC DXT,Y
  STA XX,X
  CMP #2
  BCC .x1_off
  CMP #254
  BCS .x1_off
  LDA XY,X
  CLC
  ADC DYT,Y
  STA XY,X
  CMP #2
  BCC .x1_off
  CMP #174
  BCS .x1_off
  PHX
  LDA XY,X
  LSR A
  LSR A
  LSR A
  TAY
  LDA XX,X
  LSR A
  LSR A
  LSR A
  TAX
  JSR GETC
  PLX
  CMP #0
  BEQ .x1_ok
.x1_off:
  STZ XON,X
  DEC NAXE
  RTS
.x1_ok:
  DEC STEPS
  BNE .x1_m
  LDA XX,X                     ; Sir Bram?
  STA Q2
  LDA XY,X
  STA Q3
  LDA GOD
  AND #1
  BNE .x1_a
  LDA HX
  CLC
  ADC #7
  JSR ABS_X
  CMP #5
  BCS .x1_a
  LDA HY
  CLC
  ADC #8
  JSR ABS_Y
  CMP #8
  BCS .x1_a
  STZ XON,X
  DEC NAXE
  LDA #3
  JMP DIES
.x1_a:
  LDY #NA-1                    ; another armor?
.x1_b:
  TYA
  CMP XO,X
  BEQ .x1_bn
  LDA AMS,Y
  CMP #1
  BNE .x1_bn
  LDA AMX,Y
  CLC
  ADC #8
  JSR ABS_X
  CMP #6
  BCS .x1_bn
  LDA AMY,Y
  CLC
  ADC #8
  JSR ABS_Y
  CMP #8
  BCS .x1_bn
  STZ XON,X
  DEC NAXE
  PHX
  TYA
  TAX
  JSR BREAK_ARMOR
  PLX
  RTS
.x1_bn:
  DEY
  BPL .x1_b
  RTS


; ===============================================================
;  THE GHOST
; ===============================================================
GHOST:
  LDA GHST
  CMP #1
  BEQ .gh_in
  LDA GHT                      ; waiting: it comes from the door when the time is out
  BNE .gh_d
  LDA GHT+1
  BEQ .gh_go
  DEC GHT+1
.gh_d:
  DEC GHT
  RTS
.gh_go:
  LDA #1
  STA GHST
  LDX ENTRY
  LDA ENT_X,X
  STA GHX
  LDA ENT_Y,X
  STA GHY
  STZ GWAIL
.gh_in:
  LDA GWAIL                    ; its wail
  BEQ .gh_w
  DEC GWAIL
  BRA .gh_s
.gh_w:
  LDX #0
  LDA GHX
  BPL .gh_ws
  INX
.gh_ws:
  LDA WH_ID,X
  BNE .gh_s
  LDA #W_GHOST
  JSR SFX_WHISTLE
  LDA #70
  STA GWAIL
.gh_s:
  LDA TICKS                    ; faster and faster
  AND #15
  BNE .gh_m
  LDA GHS
  CMP #GH_MAX
  BCS .gh_m
  INC GHS
.gh_m:
  LDA GHACC                    ; pixels: (GHACC + GHS) / 128
  CLC
  ADC GHS
  STA T0
  LDA #0
  ROL A
  STA T1
  LDA T0
  AND #127
  STA GHACC
  LDA T0
  ASL A
  LDA T1
  ROL A
  STA STEPS
  BEQ .gh_r
.gh_p:
  LDA GHX                      ; straight at him, through the walls
  CMP HX
  BEQ .gh_y
  BCC .gh_xr
  DEC GHX
  BRA .gh_y
.gh_xr:
  INC GHX
.gh_y:
  LDA GHY
  CMP HY
  BEQ .gh_n
  BCC .gh_yd
  DEC GHY
  BRA .gh_n
.gh_yd:
  INC GHY
.gh_n:
  DEC STEPS
  BNE .gh_p
.gh_r:
  RTS

; an arrow hit the ghost: away for 4 s, back faster (100 points)
GHOST_AWAY:
  LDA #2
  STA GHST
  LDA #240
  STA GHT
  STZ GHT+1
  INC GHITS
  LDA GHS
  CLC
  ADC #24
  CMP #GH_MAX
  BCC .ga_s
  LDA #GH_MAX
.ga_s:
  STA GHS
  LDA #S_POOF
  LDY GHX
  JSR BOOM_AT
  LDA #0
  LDY #1
  JMP ADD_PTS


; ===============================================================
;  ARMORS AND THE GHOST TOUCHING SIR BRAM
; ===============================================================
HITS:
  LDA GOD
  AND #1
  BNE .ht_r
  LDA HX
  STA Q2
  LDA HY
  STA Q3
  LDX #NA-1
.ht_l:
  LDA AMS,X
  CMP #1
  BNE .ht_n
  LDA AMX,X
  JSR ABS_X
  CMP #10
  BCS .ht_n
  LDA AMY,X
  JSR ABS_Y
  CMP #14
  BCS .ht_n
  LDA #2
  JMP DIES
.ht_n:
  DEX
  BPL .ht_l
  LDA GHST
  CMP #1
  BNE .ht_r
  LDA GHX
  JSR ABS_X
  CMP #10
  BCS .ht_r
  LDA GHY
  JSR ABS_Y
  CMP #12
  BCS .ht_r
  LDA #4
  JMP DIES
.ht_r:
  RTS

; A = what (DEATHS): Sir Bram is lost
DIES:
  PHX
  STA DEATHS
  LDA GSTATE
  BNE .di_r
  LDA #1
  STA GSTATE
  LDA #DIE_T
  STA GT
  LDA #S_ZAP
  LDX #2
  JSR SFX_BOOM
  LDA #W_DOWN
  LDX #2
  JSR SFX_WHISTLE
.di_r:
  PLX
  RTS


; ===============================================================
;  SPRITES
; ===============================================================
BUILD_SAT:
  STZ SPRI
  JSR HERO_SPR
  LDX #NR-1                    ; the arrows
.bs_r:
  LDA RON,X
  BEQ .bs_rn
  LDA RX,X
  CMP #8
  BCC .bs_rn
  SEC
  SBC #8
  STA OX
  LDA RY,X
  DEC A
  STA OY
  LDA RD,X
  ASL A
  ASL A
  CLC
  ADC #PT_AR
  STA ON
  LDA #11
  STA OC
  JSR ADD_SPR
.bs_rn:
  DEX
  BPL .bs_r
  LDX #NX-1                    ; the axes
.bs_x:
  LDA XON,X
  BEQ .bs_xn
  LDA XX,X
  CMP #8
  BCC .bs_xn
  SEC
  SBC #8
  STA OX
  LDA XY,X
  DEC A
  STA OY
  LDA XA,X
  AND #12
  CLC
  ADC #PT_AX
  STA ON
  LDA #9
  STA OC
  JSR ADD_SPR
.bs_xn:
  DEX
  BPL .bs_x
  JSR GHOST_SPR
  LDA SPRROT                   ; the armors, a different first one every frame
  INC A
  AND #NA-1
  STA SPRROT
  STA T7
  LDA #NA
  STA T6
.bs_k:
  LDX T7
  JSR ARMOR_SPR
  LDA T7
  INC A
  AND #NA-1
  STA T7
  DEC T6
  BNE .bs_k
  LDY SPRI
  LDA #$D0
  STA SAT_BUFFER,Y
  INY
  STY SATB
  RTS

; Sir Bram: 2 sprites (the gold parts on top of the armor)
HERO_SPR:
  LDA #15
  STA T4                       ; colour of the armor
  LDA #11
  STA T5                       ; colour of the gold
  LDA GSTATE
  BEQ .hs_a
  LDA GT                       ; lost: he flashes, then he is gone
  CMP #24
  BCS .hs_d
  RTS
.hs_d:
  LSR A
  AND #7
  TAX
  LDA DIE_COL,X
  STA T4
  STA T5
.hs_a:
  LDA HPOSE
  BEQ .hs_w
  LDA HDIR                     ; shooting: one pose a way
  ASL A
  ASL A
  ASL A
  CLC
  ADC #PT_HS
  BRA .hs_k
.hs_w:
  LDA HSTEP                    ; walking
  AND #8
  STA T0
  LDA HFACE
  ASL A
  ASL A
  ASL A
  ASL A
  ORA T0
  CLC
  ADC #PT_HW
.hs_k:
  STA ON
  LDA HX
  STA OX
  LDA HY
  CLC
  ADC #7
  STA OY
  LDA ON
  PHA
  CLC
  ADC #4
  STA ON
  LDA T5
  STA OC
  JSR ADD_SPR
  PLA
  STA ON
  LDA T4
  STA OC
  JMP ADD_SPR

; the ghost: it floats up and down, white and blue in turn
GHOST_SPR:
  LDA GHST
  CMP #1
  BNE .gs_r
  LDA GHX
  STA OX
  LDA TICKS
  LSR A
  LSR A
  AND #7
  TAX
  LDA GHY
  CLC
  ADC #7
  CLC
  ADC BOB,X
  STA OY
  LDA TICKS
  AND #8
  LSR A
  CLC
  ADC #PT_GH
  STA ON
  LDA #15
  STA OC
  LDA TICKS
  AND #4
  BEQ .gs_c
  LDA #5
  STA OC
.gs_c:
  JMP ADD_SPR
.gs_r:
  RTS

; X = armor
ARMOR_SPR:
  LDA AMS,X
  BEQ .as_r
  LDA AMX,X
  STA OX
  LDA AMY,X
  CLC
  ADC #7
  STA OY
  LDY LVI
  LDA ACOL_T,Y
  STA OC
  LDA AMS,X
  CMP #2
  BEQ .as_b
  LDA AMT,X                    ; walking
  AND #8
  LSR A
  CLC
  ADC #PT_AM
  BRA .as_k
.as_b:
  LDA AMT,X                    ; falling apart
  CMP #12
  LDA #PT_DEB
  BCS .as_k
  LDA #PT_DEB+4
.as_k:
  STA ON
  JMP ADD_SPR
.as_r:
  RTS

; OX, OY, ON, OC: one sprite more (keeps X)
ADD_SPR:
  LDY SPRI
  CPY #128
  BCS .ad_full
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
.ad_full:
  RTS


; ===============================================================
;  SCREEN: VRAM, texts, sprites, sound (from cheese chase)
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
SC_COL:     .byte 4,26                         ; score of player 1 / 2 on row 0
S_BIG = S_ZAP                                   ; (lib_sound: a big noise is not cut by a small one)
GH_MAX = 170                                    ; top speed of the ghost (1/128 of a pixel a frame)
; the cells: tile and 1 = two variants (by column and row)
;            floor wall    grate   pillar (4 quarters)                   torch
TILE_OF:    .byte $20,T_WALL,T_GRATE,T_PIL,T_PIL+1,T_PIL+2,T_PIL+3,T_TORCH
VAR_OF:     .byte 0,1,0,0,0,0,0,0
; MAP: the start of every row (0-21)
MR_LO:      .byte <(MAP+0),<(MAP+32),<(MAP+64),<(MAP+96),<(MAP+128),<(MAP+160),<(MAP+192),<(MAP+224)
            .byte <(MAP+256),<(MAP+288),<(MAP+320),<(MAP+352),<(MAP+384),<(MAP+416),<(MAP+448),<(MAP+480)
            .byte <(MAP+512),<(MAP+544),<(MAP+576),<(MAP+608),<(MAP+640),<(MAP+672)
MR_HI:      .byte >(MAP+0),>(MAP+32),>(MAP+64),>(MAP+96),>(MAP+128),>(MAP+160),>(MAP+192),>(MAP+224)
            .byte >(MAP+256),>(MAP+288),>(MAP+320),>(MAP+352),>(MAP+384),>(MAP+416),>(MAP+448),>(MAP+480)
            .byte >(MAP+512),>(MAP+544),>(MAP+576),>(MAP+608),>(MAP+640),>(MAP+672)
; colour table of the two wall tiles in the three thirds
WC_LO:      .byte <($2000+T_WALL*8),<($2800+T_WALL*8),<($3000+T_WALL*8)
WC_HI:      .byte >($2000+T_WALL*8)|$40,>($2800+T_WALL*8)|$40,>($3000+T_WALL*8)|$40
; the colour of the walls in the 4 wings (two rows of halls each): grey, sandstone, red brick, blue stone
WING_COL:   .byte $E1,$A1,$61,$41

; the doors: first cell, the 4 cells go down (left, right) or along (top, bottom)
DOOR_C:     .byte 0,31,14,14
DOOR_R:     .byte 9,9,0,21
; Sir Bram (and the ghost) come in here: left x, top y
ENT_X:      .byte 6,234,120,120
ENT_Y:      .byte 80,80,10,150
; the bays next to the door: no armor there
EXCL_A:     .byte 4,7,1,9
EXCL_B:     .byte 4,7,2,10
; the 12 bays (row * 4 + column): centre in pixels; a pillar: its top left cell
BAY_CX:     .byte 36,100,160,220, 36,100,160,220, 36,100,160,220
BAY_CY:     .byte 32,32,32,32, 88,88,88,88, 144,144,144,144
PIL_C:      .byte 3,12,19,26, 3,12,19,26, 3,12,19,26
PIL_R:      .byte 3,3,3,3, 10,10,10,10, 17,17,17,17
; the 6 posts between the bays
POST_C:     .byte 8,16,23,8,16,23
POST_R:     .byte 7,7,7,14,14,14
; the torches on the outer walls
TORCH_C:    .byte 4,27,4,27,0,0,31,31
TORCH_R:    .byte 0,0,21,21,4,17,4,17

; the 8 ways: right, up-right, up, up-left, left, down-left, down, down-right
DXT:        .byte 1,1,0,$FF,$FF,$FF,0,1
DYT:        .byte 0,$FF,$FF,$FF,0,1,1,1
DX4:        .byte 4,3,0,$FD,$FC,$FD,0,3        ; the arrows
DY4:        .byte 0,$FD,$FC,$FD,0,3,4,3
DX6:        .byte 7,5,0,$FB,$F9,$FB,0,5        ; where an arrow starts (from the middle of Sir Bram)
DY6:        .byte 0,$FB,$F9,$FB,0,5,7,5
; joystick (1 up 2 down 4 left 8 right) -> way ($FF = none)
JOYDIR:     .byte $FF,2,6,$FF,4,3,5,4,0,1,7,0,$FF,2,6,$FF
; the ghost floats: offsets of y
BOB:        .byte 0,1,2,1,0,$FF,$FE,$FF
; Sir Bram lost: his colours
DIE_COL:    .byte 15,5,7,15,4,5,15,7

; danger of the hall (halls entered, 15 at most)
NARM_T:     .byte 4,4,5,5,6,6,6,7,7,7,8,8,8,8,8,8          ; armors
AXMAX_T:    .byte 0,0,1,1,1,2,2,2,2,3,3,3,3,3,3,3          ; axes in the air
AXP_T:      .byte 0,0,6,8,10,12,14,16,18,20,24,28,32,36,40,48   ; chance of a throw a frame (/256)
AXSF_T:     .byte 0,0,0,32,64,64,96,128,128,160,192,192,224,224,255,255   ; speed of the axes: 1 + this / 256
ASPD_T:     .byte 40,48,56,64,64,72,80,88,96,104,112,120,128,136,144,160  ; speed of the armors (/256)
SMART_T:    .byte 64,64,96,96,128,128,160,160,192,192,208,208,224,224,240,240 ; they keep off the walls (/256)
GTIME_T:    .byte 225,215,205,195,185,175,165,155,145,140,135,130,125,120,110,105 ; ghost: frames / 4
ARRN_T:     .byte 1,1,1,1,1,1,1,1,1,1,2,2,2,2,2,2          ; arrows at a time
ACOL_T:     .byte 14,14,10,10,2,2,9,9,13,13,7,7,6,6,8,8    ; colour of the armors

; title: Sir Bram (armor, gold), an armor, the ghost (sprite Y, X, pattern, colour, second frame)
TITLE_NS = 4
TITLE_SY:   .byte 47,47,47,47
TITLE_SX:   .byte 72,72,120,168
TITLE_SN:   .byte PT_HW+4,PT_HW,PT_AM,PT_GH
TITLE_SC:   .byte 11,15,14,15
TITLE_SA:   .byte 8,8,4,4

TXT_HALLH:  .byte "HALL "
TXT_PLAYERH: .byte "PLAYER "
TXT_SIR:    .byte "SIR BRAM"
TXT_BONUS:  .byte "BONUS "
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
  .byte 9,3,"HOLD A BUTTON + DIRECTION",0
  .byte 10,3,"   = SHOOT AN ARROW",0
  .byte 11,3,"NEVER TOUCH THE WALLS!",0
  .byte 13,6,"ARMOR              50",0
  .byte 14,6,"AXE IN THE AIR     20",0
  .byte 15,6,"GHOST SENT AWAY   100",0
  .byte 16,6,"EVERY ARMOR  10 EACH",0
  .byte 18,6,"A KNIGHT MORE   5000",0
  .byte $FF
TXT_OVER:
  .byte 11,11,"GAME OVER",0,$FF
TXT_OVERP:
  .byte 13,11,"PLAYER ",0,$FF
; the sign of the hall: a box on rows 9-13
TXT_SIGN:
  .byte 9,9,"              ",0
  .byte 10,9,"              ",0
  .byte 11,9,"              ",0
  .byte 12,9,"              ",0
  .byte 13,9,"              ",0
  .byte $FF

; ---------------------------------------------------------------
; music (engine from tank): per track 0 melody / 1 harmony / 2 bass
; ---------------------------------------------------------------
V0_TAB:        .byte 13, 10, 12, 0     ; volume at the attack of the note
FLOOR_TAB:     .byte 10, 8, 9, 0       ; lowest volume reached by the decay (organ: it holds)
DECMASK_TAB:   .byte 7, 15, 15, 0      ; the volume drops by 1 when (age AND mask) = 0
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
;  GRAPHICS, HALLS AND SOUND TABLES (generated)
; ===============================================================
; HAUNTED KEEP: generated by dev/gen_haunted_keep.js (do not edit by hand)

; sprite patterns (16x16), value = pattern number * 4; tiles
T_WALL = 96
T_GRATE = 98
T_TORCH = 99
T_PIL = 100
T_LIFE = 104
PT_HW = 0
PT_HS = 32
PT_AM = 96
PT_DEB = 104
PT_GH = 112
PT_AR = 120
PT_AX = 152
NSEG = 17
BIGT = 200
BIGB = 220
SPR_LEN = 1344
SPR_PAGES = 6
SPRITES:
  .byte $00,$01,$07,$07,$07,$03,$0F,$1B,$1B,$10,$03,$03,$06,$06,$04,$0C,$00,$C0,$E0,$20,$E0,$C0,$F0,$D8,$D8,$08,$C0,$60,$30,$30,$10,$18
  .byte $03,$06,$00,$00,$00,$00,$00,$00,$00,$03,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$C0,$00,$00,$00,$00,$00,$00
  .byte $00,$01,$07,$07,$07,$03,$0F,$0F,$0F,$08,$03,$03,$03,$03,$02,$06,$00,$C0,$E0,$20,$E0,$C0,$F0,$E0,$E0,$10,$C0,$C0,$40,$40,$40,$60
  .byte $03,$06,$00,$00,$00,$00,$00,$00,$00,$03,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$C0,$00,$00,$00,$00,$00,$00
  .byte $00,$03,$07,$04,$07,$03,$0F,$1B,$1B,$10,$03,$06,$0C,$0C,$08,$18,$00,$80,$E0,$E0,$E0,$C0,$F0,$D8,$D8,$08,$C0,$C0,$60,$60,$20,$30
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$03,$00,$00,$00,$00,$00,$00,$C0,$60,$00,$00,$00,$00,$00,$00,$00,$C0,$00,$00,$00,$00,$00,$00
  .byte $00,$03,$07,$04,$07,$03,$0F,$07,$07,$08,$03,$03,$02,$02,$02,$06,$00,$80,$E0,$E0,$E0,$C0,$F0,$F0,$F0,$10,$C0,$C0,$C0,$C0,$40,$60
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$03,$00,$00,$00,$00,$00,$00,$C0,$60,$00,$00,$00,$00,$00,$00,$00,$C0,$00,$00,$00,$00,$00,$00
  .byte $00,$01,$07,$07,$07,$03,$07,$07,$07,$00,$03,$03,$06,$06,$04,$0C,$00,$C0,$E0,$20,$E0,$C0,$E0,$F8,$E0,$00,$C0,$60,$30,$30,$10,$18
  .byte $03,$06,$00,$00,$00,$00,$00,$00,$00,$03,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$08,$08,$04,$04,$04,$C8,$08,$00,$00,$00,$00,$00
  .byte $00,$01,$07,$07,$07,$03,$07,$07,$07,$00,$03,$03,$06,$06,$04,$0C,$00,$C0,$E0,$28,$F0,$E0,$E0,$E0,$E0,$00,$C0,$60,$30,$30,$10,$18
  .byte $03,$06,$00,$00,$00,$00,$00,$00,$00,$03,$00,$00,$00,$00,$00,$00,$40,$28,$04,$02,$00,$02,$01,$00,$00,$C0,$00,$00,$00,$00,$00,$00
  .byte $00,$01,$06,$01,$07,$03,$07,$07,$07,$00,$03,$03,$06,$06,$04,$0C,$00,$C0,$20,$80,$E0,$C0,$E0,$E0,$E0,$00,$C0,$60,$30,$30,$10,$18
  .byte $03,$06,$01,$06,$00,$00,$00,$00,$00,$03,$00,$00,$00,$00,$00,$00,$00,$00,$C0,$30,$00,$00,$00,$00,$00,$C0,$00,$00,$00,$00,$00,$00
  .byte $00,$03,$07,$14,$0F,$07,$07,$07,$07,$00,$03,$06,$0C,$0C,$08,$18,$00,$80,$E0,$E0,$E0,$C0,$E0,$E0,$E0,$00,$C0,$C0,$60,$60,$20,$30
  .byte $02,$14,$20,$40,$00,$40,$80,$00,$00,$03,$00,$00,$00,$00,$00,$00,$C0,$60,$00,$00,$00,$00,$00,$00,$00,$C0,$00,$00,$00,$00,$00,$00
  .byte $00,$03,$07,$04,$07,$03,$07,$1F,$07,$00,$03,$06,$0C,$0C,$08,$18,$00,$80,$E0,$E0,$E0,$C0,$E0,$E0,$E0,$00,$C0,$C0,$60,$60,$20,$30
  .byte $00,$00,$00,$00,$10,$10,$20,$20,$20,$13,$10,$00,$00,$00,$00,$00,$C0,$60,$00,$00,$00,$00,$00,$00,$00,$C0,$00,$00,$00,$00,$00,$00
  .byte $00,$03,$07,$04,$07,$03,$07,$07,$07,$04,$0B,$16,$0C,$08,$08,$18,$00,$80,$E0,$E0,$E0,$C0,$E0,$E0,$E0,$00,$C0,$C0,$60,$60,$20,$30
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$80,$43,$00,$40,$20,$14,$02,$00,$C0,$60,$00,$00,$00,$00,$00,$00,$00,$C0,$00,$00,$00,$00,$00,$00
  .byte $00,$01,$07,$07,$07,$03,$07,$07,$07,$00,$03,$01,$06,$06,$04,$0C,$00,$C0,$E0,$20,$E0,$C0,$E0,$E0,$E0,$80,$C0,$C0,$30,$30,$10,$18
  .byte $03,$06,$00,$00,$00,$00,$00,$00,$00,$03,$00,$06,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$40,$00,$30,$C0,$00,$00,$00
  .byte $00,$01,$07,$07,$07,$03,$07,$07,$07,$00,$03,$03,$06,$06,$04,$0C,$00,$C0,$E0,$20,$E0,$C0,$E0,$E0,$E0,$20,$D0,$68,$30,$10,$10,$18
  .byte $03,$06,$00,$00,$00,$00,$00,$00,$00,$03,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$C2,$00,$02,$04,$28,$40,$00
  .byte $03,$07,$0D,$0F,$05,$03,$3F,$77,$67,$65,$47,$06,$06,$06,$0E,$0E,$C0,$E0,$B0,$F0,$A0,$C0,$FC,$EE,$E6,$A6,$E2,$60,$60,$60,$70,$70
  .byte $03,$07,$0D,$0F,$05,$03,$3F,$77,$67,$35,$27,$06,$0C,$0C,$1C,$1C,$C0,$E0,$B0,$F0,$A0,$C0,$FC,$EE,$E6,$AC,$E4,$60,$30,$30,$38,$38
  .byte $00,$03,$10,$00,$67,$07,$20,$0D,$0D,$30,$00,$0E,$1E,$00,$38,$39,$00,$00,$20,$30,$80,$8C,$00,$90,$80,$18,$38,$00,$70,$F0,$0C,$9C
  .byte $00,$00,$20,$00,$81,$00,$10,$00,$03,$40,$00,$18,$3B,$00,$73,$F7,$00,$00,$04,$00,$81,$00,$08,$00,$C0,$02,$00,$18,$DC,$00,$3C,$EF
  .byte $07,$1F,$3F,$39,$79,$7F,$7C,$7C,$7F,$FF,$FF,$FF,$FF,$FF,$DD,$88,$E0,$F8,$FC,$9C,$9E,$FE,$3E,$3E,$FE,$FF,$FF,$FF,$FF,$FF,$BB,$88
  .byte $07,$1F,$3F,$39,$79,$7F,$7C,$7C,$7F,$FF,$FF,$FF,$FF,$FF,$BB,$22,$E0,$F8,$FC,$9C,$9E,$FE,$3E,$3E,$FE,$FF,$FF,$FF,$FF,$FF,$76,$22
  .byte $00,$00,$00,$00,$00,$00,$00,$18,$1F,$18,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$10,$08,$FC,$08,$10,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$02,$04,$18,$08,$00,$00,$00,$00,$00,$00,$A8,$10,$28,$40,$88,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$01,$02,$00,$00,$00,$00,$00,$00,$01,$01,$00,$00,$00,$00,$00,$80,$C0,$A0,$80,$80,$80,$80,$80,$80,$C0,$C0,$00,$00
  .byte $00,$00,$00,$00,$0A,$04,$0A,$01,$08,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$80,$00,$00,$00,$80,$40,$20,$10,$0C,$08,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$04,$08,$1F,$08,$04,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$0C,$FC,$0C,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$08,$01,$0A,$04,$0A,$00,$00,$00,$00,$00,$00,$08,$0C,$10,$20,$40,$80,$00,$00,$00,$80,$00,$00,$00
  .byte $00,$00,$00,$01,$01,$00,$00,$00,$00,$00,$00,$02,$01,$00,$00,$00,$00,$00,$00,$C0,$C0,$80,$80,$80,$80,$80,$80,$A0,$C0,$80,$00,$00
  .byte $00,$00,$00,$08,$18,$04,$02,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$88,$40,$28,$10,$A8,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$01,$00,$01,$02,$04,$08,$00,$00,$00,$00,$00,$00,$00,$00,$60,$F0,$F8,$F8,$70,$40,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$04,$02,$01,$00,$00,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$A0,$70,$F8,$F8,$F0,$60,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$02,$0E,$1F,$1F,$0F,$06,$00,$00,$00,$00,$00,$00,$00,$00,$10,$20,$40,$80,$00,$80,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$06,$0F,$1F,$1F,$0E,$05,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$80,$00,$00,$80,$40,$20,$00,$00,$00,$00

; game tiles 96-104: patterns and colours
TILEP:
  .byte $FE,$FE,$FE,$00,$EF,$EF,$EF,$00,$EF,$EF,$EF,$00,$FE,$FE,$FE,$00,$92,$FF,$92,$92,$92,$FF,$92,$92,$10,$38,$3C,$18,$3C,$18,$18,$3C
  .byte $7F,$FF,$C0,$DF,$D0,$D7,$D4,$D5,$FE,$FF,$03,$FB,$0B,$EB,$2B,$AB,$D5,$D4,$D7,$D0,$DF,$C0,$FF,$7F,$AB,$2B,$EB,$0B,$FB,$03,$FF,$FE
  .byte $38,$7C,$4C,$7C,$38,$7C,$FE,$00
TILEC:
  .byte $E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$91,$B1,$A1,$81,$61,$61,$61,$61
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$E1,$E1,$F1,$F1,$F1,$F1,$F1,$F1,$E1,$E1,$E1,$E1,$E1,$E1,$41,$41,$41,$41,$E1,$E1,$E1,$E1,$41,$41,$41,$41
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1

; the wall segments between the posts: column, row, cells, 1 = along the row
SEG_C:
  .byte $08,$08,$08,$10,$10,$10,$17,$17,$17,$00,$08,$10,$17,$00,$08,$10,$17
SEG_R:
  .byte $00,$07,$0E,$00,$07,$0E,$00,$07,$0E,$07,$07,$07,$07,$0E,$0E,$0E,$0E
SEG_N:
  .byte $08,$08,$08,$08,$08,$08,$08,$08,$08,$09,$09,$08,$09,$09,$09,$08,$09
SEG_H:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$01,$01,$01,$01,$01,$01,$01

; the 64 halls: 3 bytes of segments (bit 0 of the first = segment 0), the pillars (bay + 1 in each nibble)
ROOM_D:
  .byte $50,$C0,$01,$00,$04,$07,$00,$C9,$84,$80,$00,$00,$40,$21,$00,$01
  .byte $82,$0C,$00,$17,$00,$62,$00,$00,$82,$E0,$00,$00,$12,$B0,$00,$06
  .byte $00,$9A,$00,$00,$10,$0A,$00,$07,$03,$40,$00,$00,$40,$20,$01,$17
  .byte $10,$06,$00,$06,$80,$6A,$00,$01,$50,$02,$00,$09,$16,$90,$01,$00
  .byte $06,$80,$00,$00,$14,$0C,$01,$00,$93,$00,$01,$00,$00,$70,$00,$04
  .byte $16,$98,$00,$C1,$42,$01,$00,$00,$80,$09,$00,$0C,$01,$4C,$00,$01
  .byte $06,$08,$00,$07,$90,$22,$00,$00,$02,$83,$00,$00,$01,$04,$01,$0C
  .byte $11,$10,$00,$00,$80,$22,$01,$04,$11,$91,$00,$0C,$05,$AC,$00,$91
  .byte $00,$86,$00,$49,$42,$20,$00,$01,$10,$03,$00,$00,$41,$A1,$00,$00
  .byte $11,$2D,$00,$00,$02,$03,$00,$07,$50,$D4,$00,$04,$54,$80,$00,$06
  .byte $05,$90,$01,$0C,$10,$CB,$00,$00,$01,$70,$01,$04,$01,$30,$00,$00
  .byte $81,$10,$00,$00,$C6,$88,$00,$09,$84,$40,$00,$06,$01,$70,$00,$07
  .byte $00,$48,$01,$07,$02,$84,$01,$00,$94,$14,$00,$06,$10,$04,$01,$06
  .byte $04,$89,$01,$C1,$82,$84,$00,$04,$04,$9B,$00,$00,$02,$18,$00,$00
  .byte $80,$02,$01,$00,$86,$10,$00,$09,$C0,$08,$00,$07,$11,$41,$00,$06
  .byte $02,$64,$01,$07,$90,$00,$01,$00,$02,$88,$00,$49,$80,$06,$00,$04

; big letters of the title
BIG_TOP:
  .byte $00,$18,$18,$18,$10,$18,$18,$1F,$00,$18,$18,$18,$10,$18,$18,$F8,$00,$01,$01,$06,$06,$18,$18,$18,$00,$80,$80,$60,$60,$18,$18,$18
  .byte $00,$18,$18,$18,$10,$18,$18,$18,$00,$18,$18,$18,$10,$18,$18,$18,$00,$18,$18,$18,$10,$1E,$1E,$19,$00,$18,$18,$18,$10,$18,$18,$98
  .byte $00,$1F,$1F,$01,$01,$01,$01,$01,$00,$F8,$F8,$80,$80,$80,$80,$80,$00,$1F,$1F,$18,$10,$18,$18,$1F,$00,$F8,$F8,$00,$00,$00,$00,$E0
  .byte $00,$1F,$1F,$18,$10,$18,$18,$18,$00,$E0,$E0,$18,$10,$18,$18,$18,$00,$18,$18,$18,$10,$19,$19,$1E,$00,$18,$18,$60,$60,$80,$80,$00
  .byte $00,$1F,$1F,$18,$10,$18,$18,$1F,$00,$E0,$E0,$18,$10,$18,$18,$E0
BIG_BOT:
  .byte $1F,$18,$18,$18,$10,$18,$18,$00,$78,$18,$18,$18,$10,$18,$18,$00,$18,$1F,$1F,$18,$10,$18,$18,$00,$18,$F8,$F8,$18,$10,$18,$18,$00
  .byte $18,$18,$18,$18,$10,$07,$07,$00,$18,$18,$18,$18,$10,$E0,$E0,$00,$19,$18,$18,$18,$10,$18,$18,$00,$18,$78,$78,$18,$10,$18,$18,$00
  .byte $01,$01,$01,$01,$01,$01,$01,$00,$00,$80,$80,$80,$80,$80,$80,$00,$1F,$18,$18,$18,$10,$1F,$1F,$00,$60,$00,$00,$00,$00,$F8,$F8,$00
  .byte $18,$18,$18,$18,$10,$1F,$1F,$00,$18,$18,$18,$18,$10,$E0,$E0,$00,$1E,$19,$19,$18,$10,$18,$18,$00,$00,$80,$80,$60,$60,$18,$18,$00
  .byte $1F,$18,$18,$18,$10,$18,$18,$00,$60,$00,$00,$00,$00,$00,$00,$00
TXT_BIG:
  .byte 3,4,200,201,202,203,204,205,206,207,208,209,210,211,212,213,32,32,214,215,210,211,210,211,216,217,0
  .byte 4,4,220,221,222,223,224,225,226,227,228,229,230,231,232,233,32,32,234,235,230,231,230,231,236,237,0
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
  .byte <SG0_0,<SG0_1,<SG0_2,<SG0_3,<SG1_0,<SG1_1,<SG1_2,<SG1_3
SONGP_HI:
  .byte >SG0_0,>SG0_1,>SG0_2,>SG0_3,>SG1_0,>SG1_1,>SG1_2,>SG1_3
SG0_0:
  .byte $22,$0C,$29,$0C,$27,$06,$25,$06,$24,$0C,$25,$0C,$22,$0C,$21,$18,$22,$06,$24,$06,$25,$06,$27,$06,$29,$0C,$2A,$0C,$29,$06,$27,$06
  .byte $25,$06,$24,$06,$25,$18,$2A,$0C,$29,$06,$27,$06,$29,$0C,$25,$0C,$27,$0C,$24,$06,$21,$06,$22,$18,$29,$06,$2A,$06,$29,$06,$28,$06
  .byte $29,$06,$31,$06,$30,$06,$2E,$06,$2D,$0C,$30,$0C,$2E,$24,$FF
SG0_1:
  .byte $19,$30,$19,$18,$18,$18,$19,$18,$16,$18,$18,$18,$16,$18,$16,$30,$18,$18,$19,$18,$19,$30,$18,$18,$19,$24,$FF
SG0_2:
  .byte $0A,$30,$0A,$18,$05,$18,$0A,$18,$0F,$18,$05,$18,$0A,$18,$0F,$18,$0A,$18,$05,$18,$0A,$18,$0A,$18,$0D,$18,$05,$18,$0A,$24,$FF
SG0_3:
  .byte $00,$30,$00,$30,$00,$30,$00,$30,$00,$30,$00,$30,$00,$30,$01,$0C,$00,$0C,$04,$24,$FF
SG1_0:
  .byte $29,$06,$2E,$06,$31,$06,$30,$06,$2E,$06,$2D,$06,$2E,$18,$FF
SG1_1:
  .byte $25,$18,$24,$0C,$25,$18,$FF
SG1_2:
  .byte $0A,$18,$05,$0C,$0A,$18,$FF
SG1_3:
  .byte $01,$0C,$03,$0C,$02,$0C,$04,$18,$FF

; one-shot tone effects: period and volume for every frame
WH_TL:
  .byte $00,$18,$1B,$1F,$25,$2D,$39,$45,$32,$45,$72,$45,$32,$45,$72,$45,$32,$45,$72,$45,$32,$2A,$20,$00,$95,$86,$82,$84,$80,$74,$6C,$6B
  .byte $6D,$69,$61,$5D,$5D,$5F,$5C,$57,$55,$57,$59,$56,$53,$52,$55,$58,$56,$53,$54,$59,$5C,$5A,$59,$5C,$63,$66,$65,$65,$6B,$75,$79,$78
  .byte $7A,$85,$95,$9A,$D0,$AE,$E2,$BD,$F8,$D0,$12,$E7,$32,$04,$5B,$2A,$50,$50,$50,$50,$3F,$3F,$3F,$3F,$35,$35,$35,$35,$28,$28,$28,$28
  .byte $28,$28,$28,$28,$28,$28,$23,$1C,$26,$1F,$2B,$23,$2F,$26,$34,$2A,$3A,$2F,$40,$34,$47,$3A,$4F,$40,$57,$47,$61,$4E,$6B,$57,$77,$60
  .byte $84,$6B,$92,$76,$A2,$83,$B3,$91,$C7,$A1,$DC,$B2,$F4,$C5,$3C,$3C,$3C,$3C,$00,$00,$2F,$2F,$2F,$2F,$00,$00,$28,$28,$28,$28,$00,$00
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$8E,$8E,$8E,$8E,$8E,$8E,$8E,$8E,$97,$97,$97,$97,$97,$97,$97,$97,$9F,$9F,$9F,$9F,$9F,$9F,$9F,$9F,$BD,$BD
  .byte $BD,$BD,$BD,$BD,$BD,$BD,$BD,$BD,$BD,$BD,$BD,$BD,$BD,$BD,$18,$20,$20,$50,$50,$50,$50,$3F,$3F,$3F,$3F,$35,$35,$35,$28,$28,$28,$28
  .byte $28,$28,$28,$28
WH_TH:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$00,$01,$01,$01,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00
WH_VOL:
  .byte $00,$0B,$09,$08,$06,$05,$03,$0A,$0A,$09,$09,$08,$08,$07,$07,$06,$06,$05,$05,$04,$04,$06,$04,$00,$02,$02,$03,$03,$05,$05,$06,$06
  .byte $08,$08,$09,$09,$09,$09,$08,$08,$08,$08,$07,$07,$07,$07,$06,$06,$06,$06,$05,$05,$05,$05,$04,$04,$04,$04,$03,$03,$03,$03,$02,$02
  .byte $02,$02,$02,$02,$0C,$0B,$0A,$09,$08,$07,$06,$05,$04,$03,$03,$03,$0C,$0B,$0A,$09,$0C,$0B,$0A,$09,$0C,$0B,$0A,$09,$0D,$0C,$0B,$0A
  .byte $09,$07,$06,$05,$04,$03,$0D,$0D,$0D,$0D,$0C,$0C,$0C,$0C,$0B,$0B,$0B,$0B,$0A,$0A,$0A,$0A,$09,$09,$09,$09,$08,$08,$08,$08,$07,$07
  .byte $07,$07,$06,$06,$06,$06,$05,$05,$05,$05,$04,$04,$04,$04,$0D,$0C,$0A,$09,$00,$00,$0D,$0C,$0A,$09,$00,$00,$0D,$0C,$0A,$09,$00,$00
  .byte $0D,$0B,$09,$08,$06,$04,$0C,$0B,$0A,$09,$09,$08,$07,$06,$0C,$0B,$0A,$09,$09,$08,$07,$06,$0C,$0B,$0A,$09,$09,$08,$07,$06,$0C,$0C
  .byte $0B,$0B,$0A,$0A,$0A,$09,$09,$08,$08,$08,$07,$07,$06,$06,$0A,$08,$05,$0C,$0B,$0A,$09,$0C,$0B,$0A,$09,$0C,$0B,$09,$0D,$0C,$0A,$09
  .byte $07,$06,$04,$03
WH_START:
  .byte $00,$01,$07,$15,$18,$44,$50,$66,$8E,$A6,$CE,$D1
WH_LEN:
  .byte $00,$06,$0E,$03,$2C,$0C,$16,$28,$18,$28,$03,$13
W_ARROW = 1
W_AXE = 2
W_CLANK = 3
W_GHOST = 4
W_GRATE = 5
W_BONUS = 6
W_DOWN = 7
W_EXTRA = 8
W_OVER = 9
W_KEY = 10
W_SIGN = 11

; noise effects: noise volume / period, low tone volume / period for every frame
EX_NV:
  .byte $00,$0D,$0D,$0C,$0B,$0A,$0A,$09,$08,$07,$07,$06,$05,$04,$04,$03,$02,$01,$01,$0E,$0E,$0E,$0E,$0D,$0D,$0D,$0D,$0C,$0C,$0C,$0C,$0B
  .byte $0B,$0B,$0B,$0A,$0A,$0A,$0A,$09,$09,$09,$09,$08,$08,$08,$08,$07,$07,$0A,$09,$08,$07,$06,$05,$04,$03,$02,$01,$00,$00,$0C,$0A,$08
  .byte $06,$04,$02
EX_NP:
  .byte $00,$06,$07,$08,$09,$0A,$0B,$0C,$0D,$0E,$0F,$10,$11,$12,$13,$14,$15,$16,$17,$01,$02,$03,$01,$02,$03,$01,$02,$03,$01,$02,$03,$01
  .byte $02,$03,$01,$02,$03,$01,$02,$03,$01,$02,$03,$01,$02,$03,$01,$02,$03,$0F,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19,$1A,$01,$01,$01
  .byte $01,$01,$01
EX_VC:
  .byte $00,$0B,$0A,$09,$08,$07,$06,$05,$04,$03,$02,$01,$00,$00,$00,$00,$00,$00,$00,$0A,$0A,$0A,$0A,$09,$09,$09,$09,$08,$08,$08,$08,$07
  .byte $07,$07,$07,$06,$06,$06,$06,$05,$05,$05,$05,$04,$04,$04,$04,$03,$03,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00
EX_TL:
  .byte $00,$38,$48,$59,$6B,$7E,$92,$A7,$BE,$D7,$F1,$0D,$2C,$4D,$70,$97,$C2,$F0,$23,$12,$09,$12,$09,$12,$09,$12,$09,$12,$09,$12,$09,$12
  .byte $09,$12,$09,$12,$09,$12,$09,$12,$09,$12,$09,$12,$09,$12,$09,$12,$09,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00
EX_TH:
  .byte $00,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$03,$03,$03,$03,$03,$03,$03,$04,$04,$02,$04,$02,$04,$02,$04,$02,$04,$02,$04,$02,$04
  .byte $02,$04,$02,$04,$02,$04,$02,$04,$02,$04,$02,$04,$02,$04,$02,$04,$02,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00
EX_START:
  .byte $00,$01,$13,$31,$3D
EX_LEN:
  .byte $00,$12,$1E,$0C,$06
S_BREAK = 1
S_ZAP = 2
S_POOF = 3
S_CHINK = 4

GFX_LOAD:
  .byte 1, $00,$41, <512,>512, <FONT,>FONT
  .byte 2, $00,$61, <512,>512, $F1,0
  .byte 1, $40,$46, <144,>144, <BIG_TOP,>BIG_TOP
  .byte 1, $E0,$46, <144,>144, <BIG_BOT,>BIG_BOT
  .byte 2, $40,$66, <144,>144, $71,0
  .byte 2, $E0,$66, <144,>144, $51,0
  .byte 1, $00,$43, <72,>72, <TILEP,>TILEP
  .byte 1, $00,$63, <72,>72, <TILEC,>TILEC
  .byte 2, $00,$60, <8,>8, $11,0
  .byte 1, $00,$49, <512,>512, <FONT,>FONT
  .byte 2, $00,$69, <512,>512, $F1,0
  .byte 1, $40,$4E, <144,>144, <BIG_TOP,>BIG_TOP
  .byte 1, $E0,$4E, <144,>144, <BIG_BOT,>BIG_BOT
  .byte 2, $40,$6E, <144,>144, $71,0
  .byte 2, $E0,$6E, <144,>144, $51,0
  .byte 1, $00,$4B, <72,>72, <TILEP,>TILEP
  .byte 1, $00,$6B, <72,>72, <TILEC,>TILEC
  .byte 2, $00,$68, <8,>8, $11,0
  .byte 1, $00,$51, <512,>512, <FONT,>FONT
  .byte 2, $00,$71, <512,>512, $F1,0
  .byte 1, $40,$56, <144,>144, <BIG_TOP,>BIG_TOP
  .byte 1, $E0,$56, <144,>144, <BIG_BOT,>BIG_BOT
  .byte 2, $40,$76, <144,>144, $71,0
  .byte 2, $E0,$76, <144,>144, $51,0
  .byte 1, $00,$53, <72,>72, <TILEP,>TILEP
  .byte 1, $00,$73, <72,>72, <TILEC,>TILEC
  .byte 2, $00,$70, <8,>8, $11,0
  .byte 2, $00,$78, <768,>768, $20,0
  .byte 0
