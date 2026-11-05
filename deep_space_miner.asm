;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;                                                              ;
;   DEEP SPACE MINER  -  an original space mining shooter      ;
;   65C02 assembly, TMS9918A Graphics II (tiles + sprites)     ;
;   Base: core runner (VDP, NMI + trampoline $0FD0, AY         ;
;   engine, 2 players taking turns)                            ;
;                                                              ;
;   - a miner and his drill ship work an asteroid belt. Drones ;
;     steal the crystals to build the COLOSSUS, a mechanical   ;
;     spider of 20 pieces. Shoot the asteroids, pick up the    ;
;     crystals (one crystal = one seismic charge) and blow the ;
;     colossus up, piece by piece                              ;
;   - the sector is 8 x 8 screens and wraps round; the radar   ;
;     at the top shows rocks, drones, fighters and crystals,   ;
;     the ship (yellow) and the colossus (red)                 ;
;   - drones mine the rocks or take the free crystals and      ;
;     carry them to the colossus: one crystal, one piece. When ;
;     it has all 20 pieces it wakes up and hunts the ship;     ;
;     knock all its pieces off to destroy it                   ;
;   - fighters keep close to the ship and shoot at it          ;
;   - joystick: 8 directions with inertia, button 1 = cannon   ;
;     (drills the rocks too), button 2 = seismic charge (it    ;
;     finds the colossus by itself when it is near)            ;
;   - points: crystal 200, drone 150, fighter 500, rock 50,    ;
;     piece knocked off 500, colossus 15000 + charges x 1000;  ;
;     3 lives, one more at 20000 and every 40000; 1 or 2       ;
;     players taking turns                                     ;
;   - SOUND (2 x AY-3-8910, played from the NMI at 60 Hz):     ;
;     tunes, cannon, drill, crystals, charges, metal clangs,   ;
;     the creak and the steps of the colossus, explosions      ;
;   - the main loop writes the VDP only with the interrupt     ;
;     off (VDP_INT_OFF just after the NMI); the NMI only       ;
;     copies the SAT during the vblank and plays the sound     ;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; ---------------- zero page: game ----------------
NPL         = $30      ; number of players (1-2)
CURP        = $31      ; player playing (0 / 1)
LIVES       = $32      ; 2 bytes: lives left to every player
SCL         = $34      ; 2 bytes: score per player (BCD): tens and units
SCM         = $36      ; thousands and hundreds
SCH         = $38      ; hundred thousands and ten thousands
HISC        = $3A      ; 3 bytes BCD (low, middle, high)
SECTOR      = $40      ; ---- block of the player, saved: sector 0-98
CHARGES     = $41      ;      seismic charges 0-9
NEXTX       = $42      ;      next extra life (BCD, ten thousands)
AWAKE       = $43      ;      1 = the colossus has woken up
CPBITS      = $44      ;      3 bytes: pieces of the colossus (bits)
FRESH       = $47      ;      1 = a new sector (the intro and the tune)
PBLOCK      = 8
DIFF        = $48      ; difficulty 0-15
GSTATE      = $49      ; 0 playing, 1 ship lost, 3 colossus destroyed
GT          = $4A      ; timer of GSTATE
JOYC        = $4B      ; both joysticks drive the player playing
JOYP        = $4C      ; JOYC of the frame before
HUDD        = $4D      ; 1 = the HUD changed
FIRSTT      = $4E      ; 1 = first turn of the game
SHOWP       = $4F      ; 1 = the intro before the sector
GF          = $50      ; frames of play
CAMXL       = $52      ; world position of the top left pixel of the screen
CAMXH       = $53
CAMYL       = $54
CAMYH       = $55
HDIR        = $56      ; ship: direction 0-7 (0 up, clockwise)
FIRET       = $57      ; frames before the next shot
NPIECE      = $58      ; pieces of the colossus in place
MSGT        = $59      ; frames the message of row 23 stays
CVX         = $5A      ; colossus speed (8.8): lo, hi
CVXH        = $5B
CVY         = $5C
CVYH        = $5D
CANIM       = $5E      ; walk frame 0-1
STEPT       = $5F      ; frames to the next step
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
SLOT        = $72      ; object being moved
RR          = $73      ; first object in the SAT (turns)
CNT         = $74
BONL        = $75      ; bonus (BCD)
BONH        = $76
SONG        = $77      ; tune to play
CXF         = $78      ; colossus: world position of the top left of the picture (fraction, lo, hi)
CXL         = $79
CXH         = $7A
CYF         = $7B
CYL         = $7C
CYH         = $7D
LTX         = $7E      ; picture being drawn: tile column and row on the screen (signed)
LTY         = $7F
P_JOY       = $80      ; 2 bytes (joystick, 1 = pressed)
PTS_L       = $82      ; points to add (BCD)
PTS_M       = $83
PTS_H       = $84
SATB        = $85      ; bytes of the SAT to copy
HOFF        = $86      ; name table of NT_XY and CLEAR_NT (always 0 here)
LSH         = $87      ; picture: shift 0-3 (2 pixels each), row offset 0-7
LDYO        = $88
OTX         = $89      ; picture shown: tile column and row
OTY         = $8A
OVIS        = $8B      ; 1 = a picture is shown
LVIS        = $8C      ; 1 = the picture being drawn is on the screen
FB          = $8D      ; 2 bytes: picture (walk frame, shift)
FO          = $8F      ; 2 bytes: owners
BASE        = $91      ; first tile code of the hidden set
SET         = $92      ; tile set shown: 0 = T_COLA, 1 = T_COLB
XMIN        = $93      ; SHOW: rectangle to write
XMAX        = $94
YMIN        = $95
YMAX        = $96
CROW        = $97
RELX        = $98      ; 2 bytes: object - camera (signed)
RELY        = $9A      ; 2 bytes
DXT         = $9C      ; AIM: difference, then direction 0-15
DYT         = $9D
SITEXL      = $9E      ; where the colossus is built (top left of the picture)
SITEXH      = $9F
SITEYL      = $A0
SITEYH      = $A1
NVIS        = $A2      ; visible targets (rocks, drones, fighters) in VLIST
FTIME       = $A3      ; frames between the shots of a fighter
ESC         = $A4      ; 1 = a message about the colossus has been shown
DEATH       = $A5      ; why the ship was lost (for the tests): 1 colossus, 2 fighter, 3 shot
CSPD        = $A6      ; colossus speed: 0 slow, 1 mid, 2 fast
NDRONE      = $A7      ; drones and fighters of the sector
NFIGHT      = $A8
NROCK       = $A9
HXS         = $AA      ; ship centre on the screen (constant)
HYS         = $AB
NSL         = $AF      ; objects in SLIST
ROCKD       = $E5      ; 1 = the rocks of the radar must be drawn again
MISS0       = $EA      ; pieces missing (bits 0-19)
MISS1       = $EB
MISS2       = $EC
CIDX        = $EE      ; index into CM0-2 of the row being copied
CPH         = $EF      ; frame of the picture 0-2

HX_SCR      = 128      ; the ship stays at the centre of the playfield
HY_SCR      = 104

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
OX         = $E0         ; sprite being added: X on the screen, feet, pattern, colour
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

; ---------------- objects: 48 slots, one byte per field ----------------
;   0 ship, 1-4 shots, 5-6 charges, 7-22 rocks, 23-28 drones, 29-32 fighters,
;   33-36 enemy shots, 37-42 crystals, 43-47 explosions
NOB        = 48
O_K        = $0200       ; kind (K_*, 0 = free)
O_XF       = $0230       ; world x: fraction, lo, hi (0-2047)
O_XL       = $0260
O_XH       = $0290
O_YF       = $02C0       ; world y: fraction, lo, hi (0-1535)
O_YL       = $02F0
O_YH       = $0320
O_VXL      = $0350       ; speed 8.8 (signed)
O_VXH      = $0380
O_VYL      = $03B0
O_VYH      = $03E0
O_T        = $0410       ; timer
O_H        = $0440       ; hits / ore left
O_S        = $0470       ; state
O_C        = $04A0       ; target / carried crystal / kind to come back
O_SX       = $04D0       ; centre on the screen (when O_V = 1)
O_SY       = $0500
O_V        = $0530       ; 1 = on the screen

G_SHOT     = 1           ; first slot of every group
G_CHARGE   = 5
G_ROCK     = 7
G_DRONE    = 23
G_FIGHT    = 29
G_ESHOT    = 33
G_CRYS     = 37
G_BOOM     = 43

K_SHIP     = 1
K_SHOT     = 2
K_CHARGE   = 3
K_ROCK     = 4
K_DRONE    = 5
K_FIGHTER  = 6
K_ESHOT    = 7
K_CRYS     = 8
K_BOOM     = 9
K_WAIT     = 10          ; a rock, drone or fighter that comes back later (O_C = kind)

; ---------------- other RAM ----------------
N_X        = $0560       ; near stars (16): position in a 256 x 256 field, cell drawn (hi 0 = none), code
N_Y        = $0570
N_AL       = $0580
N_AH       = $0590
N_CD       = $05A0
F_X        = $05B0       ; far stars (12)
F_Y        = $05BC
F_AL       = $05C8
F_AH       = $05D4
F_CD       = $05E0
VLIST      = $05EC       ; visible rocks, drones, fighters (slots, at most 20)
SAT_BUFFER = $0600       ; 32 sprites x 4 + end of list
RADB       = $0690       ; radar picture: 12 tiles x 8 rows
PRESENT    = $0740       ; 21 bytes: $FF piece there, $00 missing (20 = empty byte)
PSAVE      = $0760       ; 2 x 16: block of every player
RUNS       = $0780       ; picture: runs of rows in the same third (at most 2): first row, rows, third
RUNN       = $0782
RUNT       = $0784
NRUN       = $0786
SLIST      = $0790       ; objects on the screen (sprites), at most 47
RADR       = $0800       ; radar: the rocks (12 tiles x 8 rows), drawn again when they change

NSTAR      = 10
NFAR       = 6

; ---------------- parameters ----------------
BTN_MASK    = %00110000

; ---------------- records on the SD (lib_records.asm) ----------------
REC_ZONE    = 27         ; fixed zone of the game in the save area
REC_RAM     = $7C00      ; $2A0 bytes after the program
REC_ROW     = 9          ; table on rows 9-17 of the title
REC_WIPEN   = 11         ; rows 9-19 of the title give way to the table
REC_JOY2    = $FF        ; both joysticks drive the player playing
REC_SROW    = REC_ROW    ; table header on the sign screen
ACC         = $12        ; thrust per frame (fraction of a pixel)
VMAX        = $02        ; top speed: 2.5 pixels per frame (integer part, and $80)
SHOT_T      = 26         ; frames a shot flies
CHARGE_T    = 150
CRYS_T      = 240        ; a free crystal lasts 4 x 240 frames
WAIT_T      = 255        ; frames before a rock / drone / fighter comes back

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
  STA HOFF
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
;  TITLE: the name, what things are worth
; ===============================================================
TITLE:
  LDX #$FF
  TXS
  JSR HIDE_SPRITES
  LDA #CMD_GAME
  STA SND_CMD
  JSR VDP_INT_OFF
  JSR CLEAR_NT
  JSR CLEAR_RADAR
  LDA #$00                     ; big letters over the near stars of third 0
  STA T0
  LDA #$43
  STA T1
  LDA #<BIG_LEN
  STA T2
  LDA #>BIG_LEN
  STA T3
  LDA #<BIG_P
  STA PTR
  LDA #>BIG_P
  STA PTR+1
  JSR VCOPY
  LDA #$00
  STA T0
  LDA #$63
  STA T1
  LDA #<BIG_LEN
  STA T2
  LDA #>BIG_LEN
  STA T3
  LDA #<BIG_C
  STA PTR
  LDA #>BIG_C
  STA PTR+1
  JSR VCOPY
  JSR DRAW_TOP
  LDA #<TXT_BIG
  STA TP
  LDA #>TXT_BIG
  STA TP+1
  JSR PRINT
  JSR TITLE_PAGE
  JSR REC_TITLE
  LDA #2                       ; the title tune
  STA SONG
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

; rows 9-19 of the title and the sprites beside them (VDP interrupt off)
TITLE_PAGE:
  JSR REC_WIPE
  LDA #<TXT_TITLE
  STA TP
  LDA #>TXT_TITLE
  STA TP+1
  JSR PRINT
  LDX #$00                     ; the ship and the others (sprites)
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
  CPX #6
  BNE .ti_s
  LDA #$D0
  STA SAT_BUFFER,Y
  INY
  STY SATB
  RTS

; one frame of the title: the ship turns, the others blink;
; every 5 s the title page and the table of the records take turns
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
  LDA FRAME_CNT
  LSR A
  LSR A
  AND #$1C                     ; ship: a direction every 8 frames
  STA SAT_BUFFER+2
  LDA FRAME_CNT
  AND #$10
  LSR A
  LSR A                        ; 0 or 4: the second pattern
  STA T0
  LDA #PT_CRYS
  CLC
  ADC T0
  STA SAT_BUFFER+6
  LDA #PT_DRONE
  CLC
  ADC T0
  STA SAT_BUFFER+10
  LDA #PT_FIGHTER
  CLC
  ADC T0
  STA SAT_BUFFER+14
  LDA #PT_CHARGE
  CLC
  ADC T0
  STA SAT_BUFFER+22
  JMP VDP_INT_ON


; ===============================================================
;  NEW GAME: sector 1, 3 lives for every player
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
  LDA NPL
  STA CURP
.ng_w:
  DEC CURP                     ; player NPL-1 ... 0
  LDX CURP
  LDA #3
  STA LIVES,X
  STZ SECTOR
  LDA #3                       ; three charges to start with
  STA CHARGES
  LDA #$02                     ; first extra life at 20000
  STA NEXTX
  LDA #1
  STA FRESH
  JSR SAVE_PLAYER
  LDA CURP
  BNE .ng_w
  LDA #$01
  STA FIRSTT
  ; fall into TURN_START with CURP = 0


; ===============================================================
;  TURN OF A PLAYER, then the sector
; ===============================================================
TURN_START:
  LDX CURP
  JSR LOAD_PLAYER
  STZ SHOWP
  LDA NPL
  CMP #$02
  BNE STAGE_START
  INC SHOWP

STAGE_START:
  LDX #$FF
  TXS
  JSR HIDE_SPRITES
  JSR VDP_INT_OFF
  LDA #$01
  JSR SET_BACKDROP
  JSR SET_SECTOR
  LDA FRESH
  BEQ .ss_old
  INC SHOWP                    ; a new sector: the intro, the colossus starts from nothing
  STZ AWAKE
  STZ CPBITS
  STZ CPBITS+1
  STZ CPBITS+2
  LDA SECTOR                   ; every 4th sector: a swarm, the colossus is half built
  AND #3
  CMP #3
  BNE .ss_old
  LDA #$FF
  STA CPBITS
  LDA #$03
  STA CPBITS+1
.ss_old:
  LDA SHOWP
  BEQ .ss_go
  JSR INTRO
  JSR VDP_INT_ON
  LDA FIRSTT                   ; the tune: first turn or a new sector
  ORA FRESH
  BEQ .ss_short
  STZ FIRSTT
  STZ SONG
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
  LDA #120
  JSR WAIT_FRAMES
.ss_w:
  JSR VDP_INT_OFF
.ss_go:
  STZ SHOWP
  STZ FRESH
  STZ GSTATE
  LDA #CMD_GAME
  STA SND_CMD
  JSR WORLD_START
  JSR BUILD_SAT
  JSR VDP_INT_ON
  LDA #30
  JSR WAIT_FRAMES


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
  INC GF
  BNE .gl_g
  INC GF+1
.gl_g:
  LDA GSTATE
  BNE .gl_ns
  JSR SHIP_FRAME
.gl_ns:
  JSR CAMERA
  JSR COLOSSUS_FRAME
  JSR OBJECTS
  JSR STARS
  JSR COLOSSUS_DRAW
  JSR RADAR
  JSR UPDATE_HUD
  JSR BUILD_SAT
WEND:
  JSR VDP_INT_ON
  LDA JOYC
  STA JOYP
  LDA GSTATE
  BEQ GAME_LOOP
  CMP #3
  BEQ .gl_win
  DEC GT                       ; lost: the explosion goes on
  BNE GAME_LOOP
  JMP LOSE_LIFE
.gl_win:
  JMP SECTOR_CLEAR

; A = backdrop colour (R7)
SET_BACKDROP:
  STA VREG
  LDA #(VDP_REGISTER_BITS | 7)
  STA VREG
  RTS


; ===============================================================
;  THE COLOSSUS IS DESTROYED: explosions, then the bonus
; ===============================================================
SECTOR_CLEAR:
  LDA #120
  STA GT
.sc_l:                         ; 120 frames: the world goes on, explosions where it stood
  JSR VDP_INT_OFF
  JSR NEXT_RND
  INC GF
  JSR CAMERA
  JSR OBJECTS
  JSR STARS
  JSR COLOSSUS_DRAW
  LDA GT
  AND #7
  BNE .sc_nb
  JSR COLOSSUS_BOOM
  LDA GT
  AND #8
  BEQ .sc_k
  LDA #$06
  BRA .sc_bd
.sc_k:
  LDA #$01
.sc_bd:
  JSR SET_BACKDROP
.sc_nb:
  JSR BUILD_SAT
  JSR VDP_INT_ON
  DEC GT
  BNE .sc_l
  JSR VDP_INT_OFF
  LDA #$01
  JSR SET_BACKDROP
  JSR HIDE_SPRITES
  JSR CLEAR_PLAY
  LDA #<TXT_CLEAR
  STA TP
  LDA #>TXT_CLEAR
  STA TP+1
  JSR PRINT
  LDA #1
  STA SONG
  LDA #CMD_START
  STA SND_CMD
  JSR VDP_INT_ON
  LDA #60
  JSR WAIT_FRAMES
  ; ---- bonus: 15000 + charges x 1000 (the charges are spent)
  LDA #$50
  STA BONH
  LDA #$01
  STA BONL                     ; BONL = ten thousands, BONH = thousands and hundreds
  LDX CHARGES
  BEQ .sc_p
.sc_c:
  SED
  LDA BONH
  CLC
  ADC #$10
  STA BONH
  LDA BONL
  ADC #0
  STA BONL
  CLD
  DEX
  BNE .sc_c
.sc_p:
  STZ CHARGES
  JSR VDP_INT_OFF
  LDA #<TXT_BONUS
  STA TP
  LDA #>TXT_BONUS
  STA TP+1
  JSR PRINT
  LDA BONL
  JSR PUT_2
  LDA BONH
  JSR PUT_2
  LDA #'0'
  STA VDATA
  STA VDATA
  STZ PTS_L
  LDA BONH
  STA PTS_M
  LDA BONL
  STA PTS_H
  JSR ADD_SCORE
  JSR UPDATE_HUD
  JSR VDP_INT_ON
.sc_t:
  LDA #1
  JSR WAIT_FRAMES
  LDA SND_BUSY
  BNE .sc_t
  LDA #90
  JSR WAIT_FRAMES
  LDA #1                       ; the next sector
  STA FRESH
  LDA SECTOR
  CMP #98
  BCS .sc_n
  INC SECTOR
.sc_n:
  JSR SAVE_PLAYER
  JMP STAGE_START

LOSE_LIFE:
  LDX CURP
  DEC LIVES,X
  JSR PIECES_SAVE
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
  LDA #<TXT_PLAYER
  STA TP
  LDA #>TXT_PLAYER
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
  TXA                          ; extra byte: the sector reached (1-99)
  ASL A
  ASL A
  ASL A
  ASL A
  TAY
  LDA PSAVE,Y
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
REC_NAME:  .byte "DEEP SPACE MINER"
REC_HEAD:  .byte "BEST MINERS",0
REC_XLBL:  .byte "SECTOR ",0


; ===============================================================
;  INTRO: player, sector, what to do
; ===============================================================
INTRO:
  JSR CLEAR_NT
  JSR DRAW_TOP
  LDX NPL
  CPX #2
  BNE .in_g
  LDA #<TXT_PLAYER
  STA TP
  LDA #>TXT_PLAYER
  STA TP+1
  JSR PRINT
  LDA CURP
  CLC
  ADC #$31
  STA VDATA
.in_g:
  LDA #<TXT_SECTOR
  STA TP
  LDA #>TXT_SECTOR
  STA TP+1
  JSR PRINT
  LDA SECTOR
  INC A
  JSR BIN2BCD
  JSR PUT_2
  LDA SECTOR                   ; the hint: what to do, or the swarm
  AND #3
  CMP #3
  BEQ .in_sw
  LDA SECTOR
  BNE .in_n
  LDA #<TXT_H0
  STA TP
  LDA #>TXT_H0
  STA TP+1
  JMP PRINT
.in_n:
  LDA #<TXT_H1
  STA TP
  LDA #>TXT_H1
  STA TP+1
  JMP PRINT
.in_sw:
  LDA #<TXT_H2
  STA TP
  LDA #>TXT_H2
  STA TP+1
  JMP PRINT

; difficulty and the numbers of the sector
SET_SECTOR:
  LDA SECTOR
  CMP #16
  BCC .st_d
  LDA #15
.st_d:
  STA DIFF
  LSR A                        ; drones: 3 + difficulty / 2, at most 6
  CLC
  ADC #3
  CMP #7
  BCC .st_dr
  LDA #6
.st_dr:
  STA NDRONE
  LDA DIFF                     ; fighters: 1 + difficulty / 3, at most 4
  LDX #0
.st_f3:
  CMP #3
  BCC .st_f
  SBC #3
  INX
  BRA .st_f3
.st_f:
  INX
  CPX #5
  BCC .st_fs
  LDX #4
.st_fs:
  STX NFIGHT
  LDA DIFF                     ; rocks: 16 - difficulty / 2, at least 10
  LSR A
  STA T0
  LDA #16
  SEC
  SBC T0
  CMP #10
  BCS .st_r
  LDA #10
.st_r:
  STA NROCK
  LDA DIFF                     ; fighters shoot every 160 - 6 x difficulty frames
  ASL A
  ADC DIFF
  ASL A
  STA T0
  LDA #160
  SEC
  SBC T0
  STA FTIME
  LDA DIFF                     ; colossus: slow, then mid from sector 3, fast from sector 7
  LDX #0
  CMP #2
  BCC .st_c
  INX
  CMP #6
  BCC .st_c
  INX
.st_c:
  STX CSPD
  RTS


; ===============================================================
;  HUD: rows 0-2 (scores, lives, charges, sector, pieces), the radar
;  in the middle (columns 14-17), messages on row 23
; ===============================================================
DRAW_TOP:
  LDA #<TXT_TOP
  STA TP
  LDA #>TXT_TOP
  STA TP+1
  JSR PRINT
  LDX #1
  LDY #4
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
  LDX #0
  LDY #20
  JSR NT_XY
  LDA #'2'
  STA VDATA
  LDA #'U'
  STA VDATA
  LDA #'P'
  STA VDATA
  LDX #$01
  JMP DRAW_SCORE
.dt_e:
  RTS

; the radar tiles: 160-171, 4 per row at columns 14-17, rows 0-2
DRAW_RADAR:
  LDX #0
  LDY #14
  JSR NT_XY
  LDX #3
  LDA #T_RADAR
.dt_r0:
  STA VDATA
  INC A
  DEX
  BPL .dt_r0
  PHA
  LDX #1
  LDY #14
  JSR NT_XY
  PLA
  LDX #3
.dt_r1:
  STA VDATA
  INC A
  DEX
  BPL .dt_r1
  PHA
  LDX #2
  LDY #14
  JSR NT_XY
  PLA
  LDX #3
.dt_r2:
  STA VDATA
  INC A
  DEX
  BPL .dt_r2
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

; row 2 left: spare lives and charges; right: sector and pieces of the colossus
DRAW_STATUS:
  LDX #2
  LDY #1
  JSR NT_XY
  LDX CURP                     ; spare lives (at most 4)
  LDA LIVES,X
  BEQ .ds_z
  DEC A
.ds_z:
  STA T0
  LDX #0
.ds_l:
  LDA #$20
  CPX T0
  BCS .ds_b
  LDA #T_LIFE
.ds_b:
  STA VDATA
  NOP                          ; 8 cycles between two VDP writes
  NOP
  INX
  CPX #4
  BNE .ds_l
  LDA #$20
  STA VDATA
  NOP                          ; 8 cycles between two VDP writes
  NOP
  STA VDATA
  NOP                          ; 8 cycles between two VDP writes
  NOP
  LDA #T_CHG
  STA VDATA
  NOP                          ; 8 cycles between two VDP writes
  NOP
  LDA CHARGES
  ORA #$30
  STA VDATA
  NOP                          ; 8 cycles between two VDP writes
  NOP
  LDX #1
  LDY #19
  JSR NT_XY
  LDY #0
.ds_s:
  LDA TXT_SEC,Y
  BEQ .ds_se
  STA VDATA
  NOP                          ; 8 cycles between two VDP writes
  NOP
  INY
  BRA .ds_s
.ds_se:
  LDA SECTOR
  INC A
  JSR BIN2BCD
  JSR PUT_2
  LDX #2
  LDY #19
  JSR NT_XY
  LDY #0
.ds_c:
  LDA TXT_COL,Y
  BEQ .ds_ce
  STA VDATA
  NOP                          ; 8 cycles between two VDP writes
  NOP
  INY
  BRA .ds_c
.ds_ce:
  LDA NPIECE
  JSR BIN2BCD
  JSR PUT_2
  LDA #'/'
  STA VDATA
  NOP                          ; 8 cycles between two VDP writes
  NOP
  LDA #'2'
  STA VDATA
  NOP                          ; 8 cycles between two VDP writes
  NOP
  LDA #'0'
  STA VDATA
  NOP                          ; 8 cycles between two VDP writes
  NOP
  RTS

UPDATE_HUD:
  LDA HUDD
  BEQ .uh_m
  LDA LVIS                     ; the colossus on the screen: only in its lightest frame
  BEQ .uh_go
  LDA CPH
  CMP #1
  BNE .uh_m
.uh_go:
  STZ HUDD
  LDX CURP
  JSR DRAW_SCORE
  JSR DRAW_STATUS
.uh_m:
  LDA MSGT                     ; the message of row 23 goes away
  BEQ .uh_r
  DEC MSGT
  BNE .uh_r
  LDX #23
  LDY #0
  JSR NT_XY
  LDX #32
  LDA #$20
.uh_c:
  STA VDATA
  DEX
  BNE .uh_c
.uh_r:
  RTS

; A = message number: centred on row 23 for 3 seconds
MESSAGE:
  TAX
  LDA MSG_LO,X
  STA TP
  LDA MSG_HI,X
  STA TP+1
  LDX #23
  LDY #0
  JSR NT_XY
  LDX #32
  LDA #$20
.ms_c:
  STA VDATA
  DEX
  BNE .ms_c
  JSR PRINT
  LDA #180
  STA MSGT
  RTS

; the playfield (rows 3-23) to spaces, the stars forgotten
CLEAR_PLAY:
  LDA #$60
  STA T0
  LDA #(VDP_WRITE_VRAM_BIT | >VDP_NAME_TABLE_BASE)
  STA T1
  LDA #$A0
  STA T2
  LDA #$02
  STA T3
  LDA #$20
  JSR VFILL
  STZ OVIS
  LDX #NSTAR-1
.cp_n:
  STZ N_AH,X
  DEX
  BPL .cp_n
  LDX #NFAR-1
.cp_f:
  STZ F_AH,X
  DEX
  BPL .cp_f
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
  LDA SECTOR,Y
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
  STA SECTOR,Y
  INX
  INY
  CPY #PBLOCK
  BNE .lp_b
  RTS

; the pieces in place (PRESENT) into the bits CPBITS
PIECES_SAVE:
  STZ CPBITS
  STZ CPBITS+1
  STZ CPBITS+2
  LDX #NPIECES-1
.ps_l:
  LDA PRESENT,X
  BEQ .ps_n
  TXA
  LSR A
  LSR A
  LSR A
  TAY
  TXA
  AND #7
  PHX
  TAX
  LDA BITS,X
  ORA CPBITS,Y
  STA CPBITS,Y
  PLX
.ps_n:
  DEX
  BPL .ps_l
  RTS

; the bits CPBITS into PRESENT and NPIECE
PIECES_LOAD:
  STZ NPIECE
  STZ MISS0
  STZ MISS1
  STZ MISS2
  STZ PRESENT+NPIECES          ; byte with no piece
  LDX #NPIECES-1
.pl_l:
  TXA
  LSR A
  LSR A
  LSR A
  TAY
  TXA
  AND #7
  PHX
  TAX
  LDA BITS,X
  PLX
  AND CPBITS,Y
  BEQ .pl_z
  LDA #$FF
  INC NPIECE
  BRA .pl_s
.pl_z:
  PHX                          ; missing: its bit in MISS0-2
  TXA
  AND #7
  TAX
  LDA BITS,X
  ORA MISS0,Y
  STA MISS0,Y
  PLX
  LDA #0
.pl_s:
  STA PRESENT,X
  DEX
  BPL .pl_l
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
  INC LIVES,X
  SED
  LDA NEXTX
  CLC
  ADC #$04
  CLD
  BCC .as_x
  LDA #$FF                     ; past 960000: no more
.as_x:
  STA NEXTX
  LDA #W_EXTRA
  LDX #2
  JSR SFX_WHISTLE
.as_d:
  LDA #1
  STA HUDD
  PLY
  PLX
  RTS


; ===============================================================
;  WORLD: the sector, the camera, the stars, the radar
;  world x 0-2047, y 0-1535 (8 x 8 screens), both wrap round
; ===============================================================
EYEX       = $AC         ; eyes of the colossus on the screen (sprite), 1 = shown
EYEY       = $AD
EYEV       = $AE
CR         = $E8         ; cell of PUT_CELL: row, column
CC         = $E9

; a new sector or a new life: ship in the middle, rocks, drones, fighters, the colossus at its site
WORLD_START:
  JSR CLEAR_NT
  LDA #<STAR_LOAD              ; the near stars over the title letters
  STA PTR2
  LDA #>STAR_LOAD
  STA PTR2+1
  JSR LOAD_BLOCKS
  JSR CLEAR_RADAR
  LDA #1
  STA ROCKD
  JSR DRAW_TOP
  JSR DRAW_RADAR
  JSR PIECES_LOAD
  JSR DRAW_STATUS
  STZ OVIS
  STZ LVIS
  STZ SET
  STZ EYEV
  STZ MSGT
  STZ FIRET
  STZ CANIM
  STZ STEPT
  STZ CVX
  STZ CVXH
  STZ CVY
  STZ CVYH
  STZ ESC
  STZ DEATH
  STZ HUDD
  LDA #1
  STA RR
  LDX #NOB-1
.ws_o:
  STZ O_K,X
  STZ O_V,X
  STZ O_XF,X
  STZ O_YF,X
  STZ O_VXL,X
  STZ O_VXH,X
  STZ O_VYL,X
  STZ O_VYH,X
  DEX
  BPL .ws_o
  LDA #K_SHIP                  ; the ship
  STA O_K
  STZ O_XL
  LDA #4
  STA O_XH
  STZ O_YL
  LDA #3
  STA O_YH
  STZ HDIR
  JSR CAMERA
  JSR NEXT_RND                 ; the site of the colossus: far from the ship
  AND #$7F
  CLC
  ADC #$80
  STA SITEXL
  LDA #7
  STA SITEXH                   ; x 1920-2047 + ...
  JSR NEXT_RND
  AND #$7F
  STA SITEYL
  LDA #0
  STA SITEYH
  LDA SITEXL
  STA CXL
  LDA SITEXH
  STA CXH
  LDA SITEYL
  STA CYL
  LDA SITEYH
  STA CYH
  STZ CXF
  STZ CYF
  LDA AWAKE                    ; awake: it comes from the other side
  BEQ .ws_r
  LDA #1
  JSR MESSAGE
.ws_r:
  LDX #G_ROCK                  ; rocks anywhere, not too near the ship
.ws_rk:
  TXA
  SEC
  SBC #G_ROCK
  CMP NROCK
  BCS .ws_rn
  LDA #K_ROCK
  STA O_K,X
  JSR RAND_POS
  JSR NEXT_RND
  AND #3
  CLC
  ADC #8
  STA O_H,X
.ws_rn:
  INX
  CPX #G_DRONE
  BNE .ws_rk
  LDX #G_DRONE                 ; drones far away
.ws_dr:
  TXA
  SEC
  SBC #G_DRONE
  CMP NDRONE
  BCS .ws_dn
  LDA #K_DRONE
  JSR COME_BACK
.ws_dn:
  INX
  CPX #G_FIGHT
  BNE .ws_dr
  LDX #G_FIGHT                 ; fighters come after a while, one after the other
.ws_f:
  TXA
  SEC
  SBC #G_FIGHT
  CMP NFIGHT
  BCS .ws_fn
  ASL A
  ASL A
  ASL A
  ASL A
  ASL A
  ADC #120
  STA O_T,X
  LDA #K_WAIT
  STA O_K,X
  LDA #K_FIGHTER
  STA O_C,X
.ws_fn:
  INX
  CPX #G_ESHOT
  BNE .ws_f
  LDX #NSTAR-1                 ; the stars
.ws_n:
  JSR NEXT_RND
  STA N_X,X
  JSR NEXT_RND
  STA N_Y,X
  STZ N_AH,X
  DEX
  BPL .ws_n
  LDX #NFAR-1
.ws_fa:
  JSR NEXT_RND
  STA F_X,X
  JSR NEXT_RND
  STA F_Y,X
  STZ F_AH,X
  DEX
  BPL .ws_fa
  JMP OBJECTS                  ; positions on the screen for the first SAT

; X = slot: a random position at least 160 pixels from the ship
RAND_POS:
  JSR NEXT_RND
  STA O_XL,X
  JSR NEXT_RND
  AND #7
  STA O_XH,X
  JSR NEXT_RND
  STA O_YL,X
.rp_y:
  JSR NEXT_RND
  AND #7
  CMP #6
  BCS .rp_y
  STA O_YH,X
  LDA O_XH,X                   ; too near the ship (hi bytes 4 / 3): somewhere else
  CMP #4
  BNE .rp_r
  LDA O_YH,X
  CMP #3
  BEQ RAND_POS
.rp_r:
  RTS

; X = slot: a random position out of the screen (512-1535 pixels sideways, 256-767 down)
RAND_FAR:
  JSR NEXT_RND
  AND #3
  STA T0
  JSR NEXT_RND
  CLC
  ADC O_XL
  STA O_XL,X
  LDA T0
  ADC O_XH
  ADC #2
  AND #7
  STA O_XH,X
  JSR NEXT_RND
  AND #1
  STA T0
  JSR NEXT_RND
  CLC
  ADC O_YL
  STA O_YL,X
  LDA T0
  ADC O_YH
  ADC #1
  CMP #6
  BCC .rf_y
  SBC #6
.rf_y:
  STA O_YH,X
  RTS

; X = slot, A = kind: a rock, drone or fighter comes into the sector (far from the ship)
COME_BACK:
  STA O_K,X
  JSR RAND_FAR
  STZ O_VXL,X
  STZ O_VXH,X
  STZ O_VYL,X
  STZ O_VYH,X
  STZ O_S,X
  LDA #$FF
  STA O_C,X
  JSR NEXT_RND
  AND #3
  CLC
  ADC #8
  STA O_H,X                    ; rock: ore
  LDA O_K,X
  CMP #K_FIGHTER
  BNE .cb_r
  LDA #2                       ; fighter: 2 hits, its first shot
  STA O_H,X
  LDA FTIME
  STA O_T,X
.cb_r:
  RTS

; the camera: the ship at (HX_SCR, HY_SCR) on the screen
CAMERA:
  LDA O_XL
  SEC
  SBC #HX_SCR
  STA CAMXL
  LDA O_XH
  SBC #0
  AND #7
  STA CAMXH
  LDA O_YL
  SEC
  SBC #HY_SCR
  STA CAMYL
  LDA O_YH
  SBC #0
  BPL .ca_y
  LDA #5
.ca_y:
  STA CAMYH
  RTS

; X = slot: RELX / RELY = object - camera (signed, the shortest way round)
REL_OBJ:
  LDA O_XL,X
  SEC
  SBC CAMXL
  STA RELX
  LDA O_XH,X
  SBC CAMXH
  AND #7
  CMP #4
  BCC .ro_x
  ORA #$F8
.ro_x:
  STA RELX+1
  LDA O_YL,X
  SEC
  SBC CAMYL
  STA RELY
  LDA O_YH,X
  SBC CAMYH
  BPL .ro_p
  CLC
  ADC #6
.ro_p:
  CMP #3
  BCC .ro_y
  SBC #6
.ro_y:
  STA RELY+1
  RTS

; X = slot: RELX / RELY = object - point QX / QY (QXL, QXH, QYL, QYH in T4-T7)
DIFF_Q:
  LDA O_XL,X
  SEC
  SBC T4
  STA RELX
  LDA O_XH,X
  SBC T5
  AND #7
  CMP #4
  BCC .dq_x
  ORA #$F8
.dq_x:
  STA RELX+1
  LDA O_YL,X
  SEC
  SBC T6
  STA RELY
  LDA O_YH,X
  SBC T7
  BPL .dq_p
  CLC
  ADC #6
.dq_p:
  CMP #3
  BCC .dq_y
  SBC #6
.dq_y:
  STA RELY+1
  RTS

; the point Q = the centre of the colossus / the ship / object Y
Q_COLOSSUS:
  LDA CXL
  STA T4
  LDA CXH
  STA T5
  LDA CYL
  STA T6
  LDA CYH
  STA T7
  RTS
Q_SHIP:
  LDY #0
Q_OBJ:
  LDA O_XL,Y
  STA T4
  LDA O_XH,Y
  STA T5
  LDA O_YL,Y
  STA T6
  LDA O_YH,Y
  STA T7
  RTS

; RELX / RELY -> RELX / RELY negated (the other way)
NEG_REL:
  LDA #0
  SEC
  SBC RELX
  STA RELX
  LDA #0
  SBC RELX+1
  STA RELX+1
  LDA #0
  SEC
  SBC RELY
  STA RELY
  LDA #0
  SBC RELY+1
  STA RELY+1
  RTS

; carry clear if |RELX| < A and |RELY| < A (A < 128)
NEAR_REL:
  STA T3
  LDA RELX+1
  BEQ .nr_xp
  CMP #$FF
  BNE .nr_no
  LDA #0
  SEC
  SBC RELX
  BEQ .nr_no
  BRA .nr_xc
.nr_xp:
  LDA RELX
.nr_xc:
  CMP T3
  BCS .nr_no
  LDA RELY+1
  BEQ .nr_yp
  CMP #$FF
  BNE .nr_no
  LDA #0
  SEC
  SBC RELY
  BEQ .nr_no
  BRA .nr_yc
.nr_yp:
  LDA RELY
.nr_yc:
  CMP T3
  RTS
.nr_no:
  SEC
  RTS

; RELX / RELY (target - source) -> A = direction 0-15 (0 up, clockwise)
AIM:
.am_s:                         ; halve both until they fit in -47..47
  LDA RELX+1
  BEQ .am_xp
  CMP #$FF
  BNE .am_half
  LDA RELX
  CMP #$D1
  BCC .am_half
  BRA .am_y
.am_xp:
  LDA RELX
  CMP #48
  BCS .am_half
.am_y:
  LDA RELY+1
  BEQ .am_yp
  CMP #$FF
  BNE .am_half
  LDA RELY
  CMP #$D1
  BCC .am_half
  BRA .am_ok
.am_yp:
  LDA RELY
  CMP #48
  BCC .am_ok
.am_half:
  LDA RELX+1
  CMP #$80
  ROR RELX+1
  ROR RELX
  LDA RELY+1
  CMP #$80
  ROR RELY+1
  ROR RELY
  BRA .am_s
.am_ok:
  LDA RELX                     ; T0 = |dx|, T1 = |dy|
  BPL .am_ax
  EOR #$FF
  INC A
.am_ax:
  STA T0
  LDA RELY
  BPL .am_ay
  EOR #$FF
  INC A
.am_ay:
  STA T1
  LDX #0                       ; class k: 0 flat ... 4 steep
  ASL A
  ASL A
  ADC T1                       ; |dy| x 5
  CMP T0
  BCC .am_k
  INX
  LDA T1                       ; |dy| x 3 < |dx| x 2 ?
  ASL A
  ADC T1
  STA T2
  LDA T0
  ASL A
  CMP T2
  BEQ .am_k1
  BCS .am_k
.am_k1:
  INX
  LDA T0                       ; |dy| x 2 < |dx| x 3 ?
  ASL A
  ADC T0
  STA T2
  LDA T1
  ASL A
  CMP T2
  BCC .am_k
  INX
  LDA T0                       ; |dy| < |dx| x 5 ?
  ASL A
  ASL A
  ADC T0
  CMP T1
  BEQ .am_k4
  BCS .am_k
.am_k4:
  INX
.am_k:
  STX T2
  LDA RELX
  BMI .am_left
  LDA RELY
  BMI .am_ur
  LDA #4                       ; down right: 4 + k
  CLC
  ADC T2
  RTS
.am_ur:
  LDA #4                       ; up right: 4 - k
  SEC
  SBC T2
  RTS
.am_left:
  LDA RELY
  BMI .am_ul
  LDA #12                      ; down left: 12 - k
  SEC
  SBC T2
  RTS
.am_ul:
  LDA #12                      ; up left: 12 + k
  CLC
  ADC T2
  AND #15
  RTS

; X = slot, A = direction 0-15, Y = speed 0-8: the speed of the object
SET_VEL:
  STA T0
  TYA
  ASL A
  ASL A
  ASL A
  ASL A
  ORA T0
  TAY
  LDA VEL_XL,Y
  STA O_VXL,X
  LDA VEL_XH,Y
  STA O_VXH,X
  LDA VEL_YL,Y
  STA O_VYL,X
  LDA VEL_YH,Y
  STA O_VYH,X
  RTS

; X = slot: moves the object by its speed, round the sector
MOVE:
  LDY #0
  LDA O_VXH,X
  BPL .mv_x
  DEY
.mv_x:
  STY T7
  CLC
  LDA O_XF,X
  ADC O_VXL,X
  STA O_XF,X
  LDA O_XL,X
  ADC O_VXH,X
  STA O_XL,X
  LDA O_XH,X
  ADC T7
  AND #7
  STA O_XH,X
  LDY #0
  LDA O_VYH,X
  BPL .mv_y
  DEY
.mv_y:
  STY T7
  CLC
  LDA O_YF,X
  ADC O_VYL,X
  STA O_YF,X
  LDA O_YL,X
  ADC O_VYH,X
  STA O_YL,X
  LDA O_YH,X
  ADC T7
  BPL .mv_p
  LDA #5
.mv_p:
  CMP #6
  BCC .mv_e
  LDA #0
.mv_e:
  STA O_YH,X
  RTS


; ===============================================================
;  STARS: one pixel in a tile, near ones move with the camera,
;  far ones at half the speed (2 pixel steps); not under the colossus
; ===============================================================
STARS:
  LDX #NSTAR-1
.sn_l:
  LDA N_Y,X
  SEC
  SBC CAMYL
  CMP #24
  BCC .sn_off
  CMP #184
  BCS .sn_off
  STA T1                       ; y on the screen
  LSR A
  LSR A
  LSR A
  STA T3                       ; row
  LDA N_X,X
  SEC
  SBC CAMXL
  STA T0
  LSR A
  LSR A
  LSR A
  STA T2                       ; column
  STA CC
  LDA T3
  STA CR
  JSR UNDER_COL
  BCC .sn_off
  LDA T1                       ; code = T_NEAR + (y & 7) x 8 + (x & 7)
  AND #7
  ASL A
  ASL A
  ASL A
  STA T4
  LDA T0
  AND #7
  ORA T4
  ORA #T_NEAR
  STA T4
  LDA N_AH,X                   ; the same cell: only the pixel
  BEQ .sn_new
  DEC A
  CMP T3
  BNE .sn_mv
  LDA N_AL,X
  CMP T2
  BNE .sn_mv
  LDA T4
  CMP N_CD,X
  BEQ .sn_n
  BRA .sn_put
.sn_mv:
  JSR ERASE_NEAR
.sn_new:
  LDA T3
  INC A
  STA N_AH,X
  LDA T2
  STA N_AL,X
.sn_put:
  LDA T2
  STA CC
  LDA T3
  STA CR
  LDA T4
  STA N_CD,X
  JSR PUT_CELL
.sn_n:
  DEX
  BPL .sn_l
  BRA FAR_STARS
.sn_off:
  LDA N_AH,X
  BEQ .sn_n
  JSR ERASE_NEAR
  STZ N_AH,X
  BRA .sn_n

; the far stars, on odd frames
FAR_STARS:
  LDA GF
  AND #1
  BNE .fs_go
  RTS
.fs_go:
  LDA CAMXH                    ; camera / 2 (low bytes)
  LSR A
  LDA CAMXL
  ROR A
  STA T5
  LDA CAMYH
  LSR A
  LDA CAMYL
  ROR A
  STA T6
  LDX #NFAR-1
  LDA LVIS                     ; the colossus on the screen: half of them each time
  BEQ .fs_l
  LDA GF
  AND #2
  BEQ .fs_l
  LDX #NFAR/2-1
.fs_l:
  LDA F_Y,X
  SEC
  SBC T6
  CMP #24
  BCC .fs_off
  CMP #184
  BCS .fs_off
  STA T1
  LSR A
  LSR A
  LSR A
  STA T3
  LDA F_X,X
  SEC
  SBC T5
  STA T0
  LSR A
  LSR A
  LSR A
  STA T2
  STA CC
  LDA T3
  STA CR
  JSR UNDER_COL
  BCC .fs_off
  LDA T1                       ; code = T_FAR + (y & 6) x 2 + (x & 6) / 2
  AND #6
  ASL A
  STA T4
  LDA T0
  AND #6
  LSR A
  ORA T4
  CLC
  ADC #T_FAR
  STA T4
  LDA F_AH,X
  BEQ .fs_new
  DEC A
  CMP T3
  BNE .fs_mv
  LDA F_AL,X
  CMP T2
  BNE .fs_mv
  LDA T4
  CMP F_CD,X
  BEQ .fs_n
  BRA .fs_put
.fs_mv:
  JSR ERASE_FAR
.fs_new:
  LDA T3
  INC A
  STA F_AH,X
  LDA T2
  STA F_AL,X
.fs_put:
  LDA T2
  STA CC
  LDA T3
  STA CR
  LDA T4
  STA F_CD,X
  JSR PUT_CELL
.fs_n:
  DEX
  BPL .fs_l
  RTS
.fs_off:
  LDA F_AH,X
  BEQ .fs_n
  JSR ERASE_FAR
  STZ F_AH,X
  BRA .fs_n

; carry clear if the cell CR (row), CC (column) is under the picture of the colossus
UNDER_COL:
  LDA OVIS
  BEQ .uc_no
  LDA CC
  CLC
  ADC #8
  SEC
  SBC OTX
  CMP #7
  BCS .uc_r
  LDA CR
  CLC
  ADC #8
  SEC
  SBC OTY
  CMP #6
  RTS
.uc_no:
  SEC
.uc_r:
  RTS

; the cell of near / far star X to 0 (not if the colossus covers it now)
ERASE_NEAR:
  LDA N_AH,X
  DEC A
  STA CR
  LDA N_AL,X
  BRA ERASE_CELL
ERASE_FAR:
  LDA F_AH,X
  DEC A
  STA CR
  LDA F_AL,X
ERASE_CELL:
  STA CC
  JSR UNDER_COL
  BCC .ec_r
  LDA #0
  JMP PUT_CELL
.ec_r:
  RTS

; tile A into the cell CR (row), CC (column) (keeps X)
PUT_CELL:
  PHA
  LDA CR
  ASL A
  ASL A
  ASL A
  ASL A
  ASL A
  ORA CC
  STA VREG
  LDA CR
  LSR A
  LSR A
  LSR A
  ORA #(VDP_WRITE_VRAM_BIT | >VDP_NAME_TABLE_BASE)
  STA VREG
  PLA
  STA VDATA
  RTS


; ===============================================================
;  RADAR: 32 x 24 pixels (tiles 160-171 at columns 14-17, rows 0-2),
;  one pixel = 64 x 64 of the sector; drawn every 8 frames
; ===============================================================
CLEAR_RADAR:
  LDX #95
.cr_l:
  STZ RADB,X
  DEX
  BPL .cr_l
  ; fall into RADAR_UP

; the picture into the patterns of third 0
RADAR_UP:
  LDA #<(T_RADAR*8)
  STA VREG
  LDA #(VDP_WRITE_VRAM_BIT | >(T_RADAR*8))
  STA VREG
  LDX #0
.ru_l:
  LDA RADB,X
  STA VDATA
  INX
  CPX #96
  BNE .ru_l
  RTS

RADAR:
  LDA LVIS                     ; the colossus on the screen: the radar stops (no time left)
  BEQ .rd_go
  RTS
.rd_go:
  LDA GF                       ; every 16 frames: rocks (if changed), clear, others, upload
  AND #15
  CMP #1
  BEQ .rd_rock
  CMP #3
  BEQ .rd_clr
  CMP #5
  BEQ .rd_draw
  CMP #7
  BEQ .rd_up
  RTS
.rd_rock:
  LDA ROCKD
  BEQ .rd_r
  STZ ROCKD
  LDX #95
.rd_rc:
  STZ RADR,X
  DEX
  BPL .rd_rc
  LDX #G_ROCK
.rd_rl:
  LDA O_K,X
  CMP #K_ROCK
  BNE .rd_rn
  JSR RADAR_DOT
  ORA RADR,Y
  STA RADR,Y
.rd_rn:
  INX
  CPX #G_DRONE
  BNE .rd_rl
.rd_r:
  RTS
.rd_clr:
  LDX #95
.rd_c:
  STZ RADB,X
  DEX
  BPL .rd_c
  RTS
.rd_up:                        ; the picture with the rocks into the patterns of third 0
  LDA #<(T_RADAR*8)
  STA VREG
  LDA #(VDP_WRITE_VRAM_BIT | >(T_RADAR*8))
  STA VREG
  LDX #0
.rd_u:
  LDA RADB,X
  ORA RADR,X
  STA VDATA
  INX
  CPX #96
  BNE .rd_u
  RTS
.rd_draw:
  LDX #G_DRONE                 ; drones and fighters
.rd_o:
  LDA O_K,X
  CMP #K_DRONE
  BEQ .rd_d
  CMP #K_FIGHTER
  BNE .rd_n
.rd_d:
  JSR RADAR_DOT
  ORA RADB,Y
  STA RADB,Y
.rd_n:
  INX
  CPX #G_ESHOT
  BNE .rd_o
  LDX #G_CRYS                  ; crystals
.rd_cr:
  LDA O_K,X
  CMP #K_CRYS
  BNE .rd_cn
  JSR RADAR_DOT
  ORA RADB,Y
  STA RADB,Y
.rd_cn:
  INX
  CPX #G_BOOM
  BNE .rd_cr
  RTS

; X = slot: Y = byte of its dot on the radar, A = bit
RADAR_DOT:
  JSR RADAR_XY
  LDA T1                       ; byte = ((ry / 8) x 4 + rx / 8) x 8 + (ry & 7)
  AND #$18
  ASL A
  ASL A
  STA T2
  LDA T0
  AND #$18
  ORA T2
  STA T2
  LDA T1
  AND #7
  ORA T2
  TAY
  LDA T0
  AND #7
  STA T2
  PHX
  LDX T2
  LDA BITR,X
  PLX
  RTS

; X = slot -> T0 = radar x 0-31, T1 = radar y 0-23
RADAR_XY:
  LDA O_XL,X                   ; x / 64 = hi x 4 + lo / 64
  ROL A
  ROL A
  ROL A
  AND #3
  STA T0
  LDA O_XH,X
  ASL A
  ASL A
  ORA T0
  STA T0
  LDA O_YL,X
  ROL A
  ROL A
  ROL A
  AND #3
  STA T1
  LDA O_YH,X
  ASL A
  ASL A
  ORA T1
  STA T1
  RTS


; ===============================================================
;  THE COLOSSUS: what it does
; ===============================================================
COLOSSUS_FRAME:
  LDA AWAKE
  BNE .cf_aw
  LDA NPIECE                   ; all 20 pieces: it wakes up
  CMP #NPIECES
  BNE .cf_r
  LDA #1
  STA AWAKE
  LDA #W_CREAK
  LDX #2
  JSR SFX_WHISTLE
  LDA #0
  JSR MESSAGE
.cf_r:
  RTS
.cf_aw:
  LDA NPIECE                   ; no pieces left: destroyed
  BNE .cf_live
  LDA GSTATE
  BNE .cf_r
  LDA #3
  STA GSTATE
  RTS
.cf_live:
  LDA GSTATE                   ; it stops while the ship is lost
  BNE .cf_r
  LDA GF                       ; every 16 frames: towards the ship, a step
  AND #15
  BNE .cf_mv
  JSR Q_COLOSSUS
  LDX #0
  JSR DIFF_Q
  JSR AIM
  LDY CSPD
  LDX #0
  STA T0
  TYA
  ASL A
  ASL A
  ASL A
  ASL A
  ORA T0
  TAY
  LDA VEL_XL,Y
  STA CVX
  LDA VEL_XH,Y
  STA CVXH
  LDA VEL_YL,Y
  STA CVY
  LDA VEL_YH,Y
  STA CVYH
  LDA CANIM
  EOR #1
  STA CANIM
  LDA LVIS                     ; the step, when it is on the screen
  BEQ .cf_msg
  LDA #S_STEP
  LDX #2
  JSR SFX_BOOM
.cf_msg:
  LDA GF                       ; now and then a warning
  BNE .cf_mv
  LDA GF+1
  AND #1
  BNE .cf_mv
  JSR NEXT_RND
  AND #1
  INC A
  JSR MESSAGE
  LDA #W_CREAK
  LDX #2
  JSR SFX_WHISTLE
.cf_mv:
  LDY #0                       ; move (as MOVE, on the colossus)
  LDA CVXH
  BPL .cf_x
  DEY
.cf_x:
  STY T7
  CLC
  LDA CXF
  ADC CVX
  STA CXF
  LDA CXL
  ADC CVXH
  STA CXL
  LDA CXH
  ADC T7
  AND #7
  STA CXH
  LDY #0
  LDA CVYH
  BPL .cf_y
  DEY
.cf_y:
  STY T7
  CLC
  LDA CYF
  ADC CVY
  STA CYF
  LDA CYL
  ADC CVYH
  STA CYL
  LDA CYH
  ADC T7
  BPL .cf_p
  LDA #5
.cf_p:
  CMP #6
  BCC .cf_e
  LDA #0
.cf_e:
  STA CYH
  JSR Q_COLOSSUS               ; touching the ship?
  LDX #0
  JSR DIFF_Q
  LDA #18
  JSR NEAR_REL
  BCS .cf_rr
  LDA #1
  STA DEATH
  JMP SHIP_DIE
.cf_rr:
  RTS

; a charge hit it: three pieces fly off (500 each)
KNOCK:
  LDA #3
  STA CNT
.kn_l:
  LDA NPIECE
  BEQ .kn_e
.kn_p:
  JSR NEXT_RND
  AND #31
  CMP #NPIECES
  BCS .kn_p
  TAY
  LDA PRESENT,Y
  BEQ .kn_p
  LDA #0
  STA PRESENT,Y
  TYA
  JSR MISS_BIT
  ORA MISS0,X
  STA MISS0,X
  DEC NPIECE
  LDA #$00
  LDY #$05
  JSR ADD_PTS
  DEC CNT
  BNE .kn_l
.kn_e:
  LDA #W_CLANG
  LDX #2
  JSR SFX_WHISTLE
  LDA #1
  STA HUDD
  RTS

; a drone brought a crystal: the next piece (in BUILD_ORDER) if one is missing
ADD_PIECE:
  LDA NPIECE
  CMP #NPIECES
  BCS .ap_r
  LDX #0
.ap_l:
  LDY BUILD_ORDER,X
  LDA PRESENT,Y
  BEQ .ap_set
  INX
  CPX #NPIECES
  BNE .ap_l
  RTS
.ap_set:
  LDA #$FF
  STA PRESENT,Y
  INC NPIECE
  TYA
  JSR MISS_BIT
  EOR #$FF
  AND MISS0,X
  STA MISS0,X
  LDA #1
  STA HUDD
  LDA LVIS
  BEQ .ap_r
  LDA #W_PIECE
  LDX #2
  JSR SFX_WHISTLE
.ap_r:
  RTS

; A = piece: X = byte of MISS0-2, A = its bit
MISS_BIT:
  PHA
  LSR A
  LSR A
  LSR A
  TAX
  PLA
  AND #7
  TAY
  LDA BITS,Y
  RTS

; an explosion somewhere on the colossus
COLOSSUS_BOOM:
  LDX #G_BOOM
.cb_f:
  LDA O_K,X
  BEQ .cb_go
  INX
  CPX #NOB
  BNE .cb_f
  RTS
.cb_go:
  LDA #K_BOOM
  STA O_K,X
  LDA #16
  STA O_T,X
  STZ O_VXL,X
  STZ O_VXH,X
  STZ O_VYL,X
  STZ O_VYH,X
  JSR NEXT_RND
  AND #31
  SEC
  SBC #16
  CLC
  ADC CXL
  STA O_XL,X
  LDA CXH
  STA O_XH,X
  JSR NEXT_RND
  AND #31
  SEC
  SBC #16
  CLC
  ADC CYL
  STA O_YL,X
  LDA CYH
  STA O_YH,X
  LDA #S_BOOM
  LDX #2
  JMP SFX_BOOM


; ===============================================================
;  THE PICTURE OF THE COLOSSUS: 48 x 40 pixels in its own tiles
;  (7 columns x 6 rows), two sets used in turn, 20 times a second.
;  Frame 1: where it is and columns 0-2 of the hidden set; frame 2:
;  columns 3-4; frame 3: columns 5-6, then the name table shows the
;  new set. Every byte is kept
;  only if the piece that owns it is in place (PRESENT).
;  Tile columns and rows are kept + 8 (always positive).
; ===============================================================
COLOSSUS_DRAW:
  LDA CPH                      ; 3 frames: where + columns 0-2, columns 3-4, columns 5-6 + show
  INC A
  CMP #3
  BCC .cd_p
  LDA #0
.cd_p:
  STA CPH
  CMP #1
  BEQ .cd_1
  BCS .cd_2
  JSR LATCH
  LDA LVIS
  BEQ .cd_r
  LDX #0
  LDA #3
  JMP COLUMNS
.cd_1:
  LDA LVIS
  BEQ .cd_r
  LDX #3
  LDA #5
  JMP COLUMNS
.cd_2:
  LDA LVIS
  BEQ .cd_s
  LDX #5
  LDA #7
  JSR COLUMNS
.cd_s:
  JMP SHOW
.cd_r:
  RTS

; where the picture goes this time (LVIS = 0: not on the screen)
LATCH:
  STZ LVIS
  LDA NPIECE
  BNE .la_go
  RTS
.la_go:
  LDA CXL                      ; RELX / RELY = top left - camera
  SEC
  SBC #24
  STA T0
  LDA CXH
  SBC #0
  AND #7
  STA T1
  LDA T0
  SEC
  SBC CAMXL
  STA RELX
  LDA T1
  SBC CAMXH
  AND #7
  CMP #4
  BCC .la_x
  ORA #$F8
.la_x:
  STA RELX+1
  LDA CYL
  SEC
  SBC #20
  STA T0
  LDA CYH
  SBC #0
  BPL .la_y0
  LDA #5
.la_y0:
  STA T1
  LDA T0
  SEC
  SBC CAMYL
  STA RELY
  LDA T1
  SBC CAMYH
  BPL .la_yp
  CLC
  ADC #6
.la_yp:
  CMP #3
  BCC .la_y
  SBC #6
.la_y:
  STA RELY+1
  LDA RELX                     ; on the screen: x -48..255, y -16..183
  CLC
  ADC #48
  STA T0
  LDA RELX+1
  ADC #0
  BEQ .la_xok
  CMP #1
  BNE .la_nj
  LDA T0
  CMP #48
  BCS .la_nj
.la_xok:
  LDA RELY
  CLC
  ADC #16
  STA T0
  LDA RELY+1
  ADC #0
  BNE .la_nj
  LDA T0
  CMP #200
  BCS .la_nj
  BRA .la_vis
.la_nj:
  RTS
.la_vis:
  LDA RELX                     ; tile column + 8, shift; tile row + 8, row offset
  AND #6
  LSR A
  STA LSH
  LDA RELX+1
  LSR A
  LDA RELX
  ROR A
  LSR A
  LSR A                        ; (RELX + 64) / 8 would need 9 bits: take x / 8 signed
  CLC
  ADC #8
  STA LTX
  LDA RELY
  AND #7
  STA LDYO
  LDA RELY+1
  LSR A
  LDA RELY
  ROR A
  LSR A
  LSR A
  CLC
  ADC #8
  STA LTY
  LDA RELX+1                   ; negative x: the shifts above lost the sign bits
  BPL .la_px
  LDA LTX
  SEC
  SBC #64
  STA LTX
.la_px:
  LDA RELY+1
  BPL .la_py
  LDA LTY
  SEC
  SBC #64
  STA LTY
.la_py:
  LDA #1
  STA LVIS
  LDA CANIM                    ; FB = CO_BMP + (CANIM x 4 + LSH) x FRAME_LEN
  ASL A
  ASL A
  ORA LSH
  TAX
  LDA FRAME_LO,X
  CLC
  ADC #<CO_BMP
  STA FB
  LDA FRAME_HI,X
  ADC #>CO_BMP
  STA FB+1
  LDA FRAME_LO,X
  CLC
  ADC #<CO_OWN
  STA FO
  LDA FRAME_HI,X
  ADC #>CO_OWN
  STA FO+1
  LDA #T_COLB                  ; the hidden set
  LDX SET
  BEQ .la_b
  LDA #T_COLA
.la_b:
  STA BASE
  LDX #0                       ; runs of rows 0-5 in the playfield (rows 3-22), one per third
  STZ NRUN
  LDA #$FF
  STA T2                       ; third of the run being built
.la_r:
  TXA
  CLC
  ADC LTY
  SEC
  SBC #8                       ; screen row
  CMP #3
  BCC .la_rx
  CMP #23
  BCS .la_rx
  LSR A
  LSR A
  LSR A
  CMP T2
  BEQ .la_more
  STA T2                       ; a new run
  LDY NRUN
  STA RUNT,Y
  TXA
  STA RUNS,Y
  LDA #1
  STA RUNN,Y
  INC NRUN
  BRA .la_rx
.la_more:
  LDY NRUN
  LDA RUNN-1,Y
  INC A
  STA RUNN-1,Y
.la_rx:
  INX
  CPX #6
  BNE .la_r
  RTS
.la_no:
  RTS

; columns X to A-1 of the picture
COLUMNS:
  STA T4
.cl_l:
  STX T5
  JSR COLUMN
  LDX T5
  INX
  CPX T4
  BNE .cl_l
  RTS

; column X: rows on the playfield, from the picture (minus the row offset) through the owners
COLUMN:
  TXA                          ; on the screen? (column + 8 in 8-39)
  CLC
  ADC LTX
  CMP #8
  BCC .co_out
  CMP #40
  BCC .co_in
.co_out:
  RTS
.co_in:
  LDA COL_OFS,X                ; PTR = picture + column x CLEN + 8 - row offset, PTR2 = owners
  SEC
  SBC LDYO
  STA T0
  LDA COL_OFH,X
  SBC #0
  STA T1
  LDA FB
  CLC
  ADC T0
  STA PTR
  LDA FB+1
  ADC T1
  STA PTR+1
  LDA FO
  CLC
  ADC T0
  STA PTR2
  LDA FO+1
  ADC T1
  STA PTR2+1
  LDA COL_CODE,X
  LDY LDYO                     ; T1 = column x 6 (+ 42 with a row offset): index into CM0-2
  BEQ .co_c0
  CLC
  ADC #42
.co_c0:
  STA T1
  LDA COL_CODE,X
  CLC
  ADC BASE
  STA T6                       ; tile of row 0
  LDX #0
.co_run:
  CPX NRUN
  BCS .co_r
  STX T2
  LDA RUNS,X                   ; VRAM address: third x $800 + code x 8
  CLC
  ADC T6
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
  STA T0
  LDA RUNT,X
  ASL A
  ASL A
  ASL A
  ORA T0
  ORA #VDP_WRITE_VRAM_BIT
  STA VREG
  LDA RUNN,X
  STA T7
  LDA RUNS,X                   ; CIDX = column x 6 + row (+ 42 with a row offset)
  CLC
  ADC T1
  STA CIDX
  LDA RUNS,X                   ; bytes from row x 8
  ASL A
  ASL A
  ASL A
  TAY
.co_rw:
  LDX CIDX                     ; a missing piece in this row? copy through the owners
  LDA CM0,X
  AND MISS0
  STA T0
  LDA CM1,X
  AND MISS1
  ORA T0
  STA T0
  LDA CM2,X
  AND MISS2
  ORA T0
  BNE .co_m
  JSR ROW_FAST
  BRA .co_nr
.co_m:
  JSR ROW_MASK
.co_nr:
  INC CIDX
  DEC T7
  BNE .co_rw
.co_n:
  LDX T2
  INX
  BRA .co_run
.co_r:
  RTS

; 8 bytes of the picture from (PTR),Y: all the pieces are there
ROW_FAST:
  LDA (PTR),Y
  STA VDATA
  INY
  LDA (PTR),Y
  STA VDATA
  INY
  LDA (PTR),Y
  STA VDATA
  INY
  LDA (PTR),Y
  STA VDATA
  INY
  LDA (PTR),Y
  STA VDATA
  INY
  LDA (PTR),Y
  STA VDATA
  INY
  LDA (PTR),Y
  STA VDATA
  INY
  LDA (PTR),Y
  STA VDATA
  INY
  RTS

; 8 bytes of the picture from (PTR),Y, each one kept if its piece (PTR2),Y is there
ROW_MASK:
  LDA (PTR2),Y
  TAX
  LDA (PTR),Y
  AND PRESENT,X
  STA VDATA
  INY
  LDA (PTR2),Y
  TAX
  LDA (PTR),Y
  AND PRESENT,X
  STA VDATA
  INY
  LDA (PTR2),Y
  TAX
  LDA (PTR),Y
  AND PRESENT,X
  STA VDATA
  INY
  LDA (PTR2),Y
  TAX
  LDA (PTR),Y
  AND PRESENT,X
  STA VDATA
  INY
  LDA (PTR2),Y
  TAX
  LDA (PTR),Y
  AND PRESENT,X
  STA VDATA
  INY
  LDA (PTR2),Y
  TAX
  LDA (PTR),Y
  AND PRESENT,X
  STA VDATA
  INY
  LDA (PTR2),Y
  TAX
  LDA (PTR),Y
  AND PRESENT,X
  STA VDATA
  INY
  LDA (PTR2),Y
  TAX
  LDA (PTR),Y
  AND PRESENT,X
  STA VDATA
  INY
  RTS

; the name table: the new set where the picture is, empty cells where it was; the eyes
SHOW:
  LDA LVIS
  ORA OVIS
  BNE .sh_go
  STZ EYEV
  RTS
.sh_go:
  LDA LVIS                     ; the rectangle: new, old or both
  BEQ .sh_old
  LDA OVIS
  BNE .sh_both
  LDA LTX
  STA XMIN
  LDA LTY
  STA YMIN
  LDA LTX
  STA XMAX
  LDA LTY
  STA YMAX
  BRA .sh_wh
.sh_old:
  LDA OTX
  STA XMIN
  STA XMAX
  LDA OTY
  STA YMIN
  STA YMAX
  BRA .sh_wh
.sh_both:
  LDA LTX
  CMP OTX
  BCC .sh_x1
  LDA OTX
.sh_x1:
  STA XMIN
  LDA LTX
  CMP OTX
  BCS .sh_x2
  LDA OTX
.sh_x2:
  STA XMAX
  LDA LTY
  CMP OTY
  BCC .sh_y1
  LDA OTY
.sh_y1:
  STA YMIN
  LDA LTY
  CMP OTY
  BCS .sh_y2
  LDA OTY
.sh_y2:
  STA YMAX
.sh_wh:
  LDA XMAX                     ; width 7, height 6, clipped to columns 0-31 and rows 3-22
  CLC
  ADC #7
  CMP #40
  BCC .sh_c1
  LDA #40
.sh_c1:
  STA XMAX
  LDA YMAX
  CLC
  ADC #6
  CMP #31
  BCC .sh_c2
  LDA #31
.sh_c2:
  STA YMAX
  LDA XMIN
  CMP #8
  BCS .sh_c3
  LDA #8
  STA XMIN
.sh_c3:
  LDA YMIN
  CMP #11
  BCS .sh_c4
  LDA #11
  STA YMIN
.sh_c4:
  LDA XMAX                     ; T1 = width, T3 / T4 / T5 = empty, picture, empty cells of a row
  SEC
  SBC XMIN
  BCC .sh_jd
  BEQ .sh_jd
  STA T1
  STA T3
  STZ T4
  STZ T5
  LDA LVIS
  BEQ .sh_wd
  LDA LTX                      ; picture columns on the screen: PL = max (LTX, XMIN) .. PR = min (LTX + 7, XMAX)
  CMP XMIN
  BCS .sh_pl
  LDA XMIN
.sh_pl:
  STA T0
  LDA LTX
  CLC
  ADC #7
  CMP XMAX
  BCC .sh_pr
  LDA XMAX
.sh_pr:
  CMP T0
  BCS .sh_pk
  LDA T0
.sh_pk:
  STA T2                       ; PR
  SEC
  SBC T0
  STA T4
  LDA XMAX
  SEC
  SBC T2
  STA T5
  LDA T0
  SEC
  SBC XMIN
  STA T3
  LDA T0                       ; T6 = code of the first picture column on the screen (row 0)
  SEC
  SBC LTX
  TAY
  LDA COL_CODE,Y
  CLC
  ADC BASE
  STA T6
.sh_wd:
  LDA YMIN
  STA CROW
  CMP YMAX
  BCC .sh_row
.sh_jd:
  JMP .sh_done
.sh_row:
  LDA CROW                     ; VRAM = $3800 + (row - 8) x 32 + column - 8
  SEC
  SBC #8
  STA T7
  ASL A
  ASL A
  ASL A
  ASL A
  ASL A
  CLC
  ADC XMIN
  SEC
  SBC #8
  STA VREG
  LDA T7
  LSR A
  LSR A
  LSR A
  ORA #(VDP_WRITE_VRAM_BIT | >VDP_NAME_TABLE_BASE)
  STA VREG
  LDA LVIS                     ; a row of the picture?
  BEQ .sh_all
  LDA CROW
  SEC
  SBC LTY
  CMP #6
  BCS .sh_all
  CLC
  ADC T6
  STA T2                       ; code of this row
  LDX T3
  BEQ .sh_p
.sh_z0:
  STZ VDATA
  DEX
  BNE .sh_z0
.sh_p:
  LDX T4
  BEQ .sh_z
  LDA T2
  CLC
.sh_pc:
  STA VDATA
  ADC #6
  DEX
  BNE .sh_pc
.sh_z:
  LDX T5
  BEQ .sh_nr
.sh_z1:
  STZ VDATA
  DEX
  BNE .sh_z1
  BRA .sh_nr
.sh_all:
  LDX T1
.sh_za:
  STZ VDATA
  DEX
  BNE .sh_za
.sh_nr:
  INC CROW
  LDA CROW
  CMP YMAX
  BNE .sh_row
.sh_done:
  LDA LTX
  STA OTX
  LDA LTY
  STA OTY
  STZ EYEV
  LDA LVIS
  STA OVIS
  BEQ .sh_r
  LDA SET
  EOR #1
  STA SET
  LDA PRESENT+2                ; the red eyes go with the head
  BEQ .sh_r
  LDA LTY                      ; y = (row - 8) x 8 + offset, in the playfield
  SEC
  SBC #8
  BMI .sh_r
  ASL A
  ASL A
  ASL A
  CLC
  ADC LDYO
  CMP #24
  BCC .sh_r
  CMP #180
  BCS .sh_r
  STA EYEY
  LDA LTX                      ; x = (column - 8) x 8 + shift x 2 + 16
  CMP #6
  BCC .sh_r
  CMP #37
  BCS .sh_r
  SEC
  SBC #6
  ASL A
  ASL A
  ASL A
  STA EYEX
  LDA LSH
  ASL A
  ADC EYEX
  STA EYEX
  LDA #1
  STA EYEV
.sh_r:
  RTS


; ===============================================================
;  THE SHIP: 8 directions with inertia, cannon, seismic charges
; ===============================================================
SHIP_FRAME:
  LDA JOYC
  AND #$0F
  TAX
  LDA JOYDIR,X
  BMI .sf_fr
  STA HDIR                     ; thrust in that direction
  ASL A
  ORA #$80                     ; speed 8 = the thrust
  TAY
  CLC
  LDA O_VXL
  ADC VEL_XL,Y
  STA O_VXL
  LDA O_VXH
  ADC VEL_XH,Y
  STA O_VXH
  CLC
  LDA O_VYL
  ADC VEL_YL,Y
  STA O_VYL
  LDA O_VYH
  ADC VEL_YH,Y
  STA O_VYH
  LDX #0
  JSR CLAMP_V
  BRA .sf_mv
.sf_fr:
  LDX #0                       ; no thrust: the speed fades
  JSR FRICTION
.sf_mv:
  LDX #0
  JSR MOVE
  LDA FIRET
  BEQ .sf_f
  DEC FIRET
  BRA .sf_c
.sf_f:
  LDA JOYC                     ; button 1: cannon (held = 8 shots a second)
  AND #%00010000
  BEQ .sf_c
  LDX #G_SHOT
.sf_fs:
  LDA O_K,X
  BEQ .sf_shot
  INX
  CPX #G_CHARGE
  BNE .sf_fs
  BRA .sf_c
.sf_shot:
  LDA #K_SHOT
  STA O_K,X
  LDY #0
  JSR SPAWN_AT
  LDA HDIR
  ASL A
  LDY #7                       ; 4 pixels a frame, plus the speed of the ship
  JSR SET_VEL
  CLC
  LDA O_VXL,X
  ADC O_VXL
  STA O_VXL,X
  LDA O_VXH,X
  ADC O_VXH
  STA O_VXH,X
  CLC
  LDA O_VYL,X
  ADC O_VYL
  STA O_VYL,X
  LDA O_VYH,X
  ADC O_VYH
  STA O_VYH,X
  LDA #SHOT_T
  STA O_T,X
  LDA #7
  STA FIRET
  LDA #W_SHOT
  LDX #2
  JSR SFX_WHISTLE
.sf_c:
  LDA JOYC                     ; button 2 (pressed now): a seismic charge
  EOR JOYP
  AND JOYC
  AND #%00100000
  BEQ .sf_r
  LDA CHARGES
  BNE .sf_ch
  LDA #W_EMPTY
  LDX #2
  JMP SFX_WHISTLE
.sf_ch:
  LDX #G_CHARGE
  LDA O_K,X
  BEQ .sf_cg
  INX
  LDA O_K,X
  BNE .sf_r
.sf_cg:
  DEC CHARGES
  LDA #1
  STA HUDD
  LDA #K_CHARGE
  STA O_K,X
  LDY #0
  JSR SPAWN_AT
  LDA HDIR
  ASL A
  LDY #6                       ; 3 pixels a frame
  JSR SET_VEL
  LDA #CHARGE_T
  STA O_T,X
  LDA #W_CHARGE
  LDX #2
  JSR SFX_WHISTLE
.sf_r:
  RTS

; X = slot: speed kept within -2.5 .. 2.5 on both axes
CLAMP_V:
  LDA O_VXH,X
  BMI .cv_xn
  CMP #VMAX
  BCC .cv_y
  BNE .cv_xp
  LDA O_VXL,X
  CMP #$80
  BCC .cv_y
.cv_xp:
  LDA #$80
  STA O_VXL,X
  LDA #VMAX
  STA O_VXH,X
  BRA .cv_y
.cv_xn:
  CMP #$FD
  BCC .cv_xm
  BNE .cv_y
  LDA O_VXL,X
  CMP #$80
  BCS .cv_y
.cv_xm:
  LDA #$80
  STA O_VXL,X
  LDA #$FD
  STA O_VXH,X
.cv_y:
  LDA O_VYH,X
  BMI .cv_yn
  CMP #VMAX
  BCC .cv_r
  BNE .cv_yp
  LDA O_VYL,X
  CMP #$80
  BCC .cv_r
.cv_yp:
  LDA #$80
  STA O_VYL,X
  LDA #VMAX
  STA O_VYH,X
  RTS
.cv_yn:
  CMP #$FD
  BCC .cv_ym
  BNE .cv_r
  LDA O_VYL,X
  CMP #$80
  BCS .cv_r
.cv_ym:
  LDA #$80
  STA O_VYL,X
  LDA #$FD
  STA O_VYH,X
.cv_r:
  RTS

; X = slot: speed - speed / 32 on both axes (towards 0)
FRICTION:
  LDA O_VXH,X
  STA T1
  LDA O_VXL,X
  JSR .fr_d
  STA O_VXL,X
  LDA T1
  STA O_VXH,X
  LDA O_VYH,X
  STA T1
  LDA O_VYL,X
  JSR .fr_d
  STA O_VYL,X
  LDA T1
  STA O_VYH,X
  RTS
.fr_d:                         ; T1:A = T1:A - T1:A / 32 (small speeds go to 0)
  STA T0
  LDA T1
  STA T2
  LDA T0
  STA T3
  LDY #5
.fr_s:
  LDA T2
  CMP #$80
  ROR T2
  ROR T3
  DEY
  BNE .fr_s
  LDA T2                       ; nothing left to take: stop
  ORA T3
  BEQ .fr_z
  CMP #$FF
  BNE .fr_sub
  LDA T3
  CMP #$FF
  BNE .fr_sub
.fr_z:
  STZ T1
  LDA #0
  RTS
.fr_sub:
  LDA T0
  SEC
  SBC T3
  PHA
  LDA T1
  SBC T2
  STA T1
  PLA
  RTS

; the ship is lost: an explosion, the world goes on for a while
SHIP_DIE:
  LDA GSTATE
  BNE .sd_r
  LDA #1
  STA GSTATE
  LDA #150
  STA GT
  STZ O_VXL
  STZ O_VXH
  STZ O_VYL
  STZ O_VYH
  LDX #0
  JSR BOOM_SLOT
  LDA #W_DIE
  LDX #2
  JSR SFX_WHISTLE
  LDA #S_BIG
  LDX #2
  JSR SFX_BOOM
.sd_r:
  RTS

; X = new slot, Y = slot: same position, still
SPAWN_AT:
  LDA O_XL,Y
  STA O_XL,X
  LDA O_XH,Y
  STA O_XH,X
  LDA O_YL,Y
  STA O_YL,X
  LDA O_YH,Y
  STA O_YH,X
  LDA #$80
  STA O_XF,X
  STA O_YF,X
  STZ O_VXL,X
  STZ O_VXH,X
  STZ O_VYL,X
  STZ O_VYH,X
  STZ O_V,X
  RTS

; X = slot: an explosion where it is (keeps X)
BOOM_SLOT:
  PHX
  TXA
  TAY
  LDX #G_BOOM
.ba_f:
  LDA O_K,X
  BEQ .ba_go
  INX
  CPX #NOB
  BNE .ba_f
  PLX
  RTS
.ba_go:
  LDA #K_BOOM
  STA O_K,X
  JSR SPAWN_AT
  LDA #16
  STA O_T,X
  PLX
  RTS

; X = slot: a crystal flies out of it (keeps X)
CRYSTAL_AT:
  PHX
  TXA
  TAY
  LDX #G_CRYS
.ca_f:
  LDA O_K,X
  BEQ .ca_go
  INX
  CPX #G_BOOM
  BNE .ca_f
  PLX
  RTS
.ca_go:
  LDA #K_CRYS
  STA O_K,X
  JSR SPAWN_AT
  LDA #CRYS_T
  STA O_T,X
  JSR NEXT_RND
  AND #15
  LDY #0                       ; half a pixel a frame, it slows down
  JSR SET_VEL
  PLX
  RTS


; ===============================================================
;  OBJECTS: one routine per kind, then the place on the screen
; ===============================================================
OBJECTS:
  STZ NVIS
  STZ NSL
  LDA #HX_SCR                  ; the ship
  STA O_SX
  LDA #HY_SCR
  STA O_SY
  LDA #1
  STA O_V
  LDX #1
OB_LOOP:
  LDA O_K,X
  BEQ OB_SKIP
  STX SLOT
  CMP #K_ROCK                  ; rocks only need their place on the screen
  BEQ OB_VIS
  ASL A
  TAX
  JMP (OBJ_JT,X)
OB_SKIP:
  STZ O_V,X
  INX
  CPX #NOB
  BNE OB_LOOP
  BRA OB_END
OB_NEXT:
  LDX SLOT
  LDA O_K,X
  BEQ OB_SKIP
  CMP #K_WAIT
  BEQ OB_SKIP
OB_VIS:                        ; on the screen: x - camera 0-255, y - camera 32-195 (not over the HUD)
  LDA O_XL,X
  SEC
  SBC CAMXL
  STA T0
  LDA O_XH,X
  SBC CAMXH
  AND #7
  BNE OB_SKIP
  LDA O_YL,X
  SEC
  SBC CAMYL
  STA T1
  LDA O_YH,X
  SBC CAMYH
  BEQ .ov_y
  CMP #$FA                     ; (round the bottom of the sector)
  BNE OB_SKIP
.ov_y:
  LDA T1
  CMP #32
  BCC OB_SKIP
  CMP #196
  BCS OB_SKIP
  STA O_SY,X
  LDA T0
  STA O_SX,X
  LDA #1
  STA O_V,X
  LDY NSL                      ; the list of the sprites
  TXA
  STA SLIST,Y
  INC NSL
  LDA O_K,X                    ; rocks, drones and fighters: targets of the shots
  CMP #K_ROCK
  BCC .ov_n
  CMP #K_ESHOT
  BCS .ov_n
  LDY NVIS
  CPY #20
  BCS .ov_n
  TXA
  STA VLIST,Y
  INC NVIS
.ov_n:
  INX
  CPX #NOB
  BEQ OB_END
  JMP OB_LOOP
OB_END:
  JSR SHOT_HITS
  JMP SHIP_HITS

OB_NONE:
  JMP OB_NEXT

; X = slot: the object is gone
FREE:
  STZ O_K,X
  STZ O_V,X
  RTS

; ---- shot of the cannon
OB_SHOT:
  LDX SLOT
  JSR MOVE
  DEC O_T,X
  BNE .os_r
  JSR FREE
.os_r:
  JMP OB_NEXT

; ---- seismic charge: towards the colossus when it is near, otherwise straight on
OB_CHARGE:
  LDX SLOT
  JSR MOVE
  LDA O_T,X
  AND #3
  STA T0
  LDA NPIECE
  BEQ .oc_t
  JSR Q_COLOSSUS
  JSR DIFF_Q
  LDA #20                      ; on it: three pieces fly off
  JSR NEAR_REL
  BCS .oc_far
  JSR BOOM_SLOT
  JSR FREE
  LDA #S_BOOM
  LDX #2
  JSR SFX_BOOM
  JSR KNOCK
  JMP OB_NEXT
.oc_far:
  LDA T0                       ; every 4 frames: turn towards it, if it is within 160 pixels
  BNE .oc_t
  JSR NEG_REL
  LDA RELX+1
  CMP #$FF
  BEQ .oc_nx
  CMP #0
  BNE .oc_t
.oc_nx:
  LDA RELY+1
  CMP #$FF
  BEQ .oc_ny
  CMP #0
  BNE .oc_t
.oc_ny:
  LDA RELX
  EOR RELX+1                   ; |x| < 160 and |y| < 160, roughly
  CMP #160
  BCS .oc_t
  LDA RELY
  EOR RELY+1
  CMP #160
  BCS .oc_t
  JSR AIM
  LDX SLOT
  LDY #6
  JSR SET_VEL
.oc_t:
  LDX SLOT
  DEC O_T,X
  BNE .oc_r
  JSR BOOM_SLOT
  JSR FREE
.oc_r:
  JMP OB_NEXT

; ---- rock: it stays where it is
OB_ROCK:
  JMP OB_NEXT

; ---- explosion
OB_BOOM:
  LDX SLOT
  DEC O_T,X
  BNE .ox_r
  JSR FREE
.ox_r:
  JMP OB_NEXT

; ---- a rock, drone or fighter that comes back
OB_WAIT:
  LDX SLOT
  DEC O_T,X
  BNE .ow_r
  LDA O_C,X
  JSR COME_BACK
  LDA #1
  STA ROCKD
.ow_r:
  JMP OB_NEXT

; ---- free crystal: slows down, lasts 4 x CRYS_T frames
OB_CRYS:
  LDX SLOT
  JSR MOVE
  LDA GF
  AND #15
  BNE .ok_t
  LDA O_VXH,X                  ; speed x 3/4
  CMP #$80
  ROR A
  STA T1
  LDA O_VXL,X
  ROR A
  STA T0
  LDA T1
  CMP #$80
  ROR T1
  ROR T0
  LDA O_VXL,X
  SEC
  SBC T0
  STA O_VXL,X
  LDA O_VXH,X
  SBC T1
  STA O_VXH,X
  LDA O_VYH,X
  CMP #$80
  ROR A
  STA T1
  LDA O_VYL,X
  ROR A
  STA T0
  LDA T1
  CMP #$80
  ROR T1
  ROR T0
  LDA O_VYL,X
  SEC
  SBC T0
  STA O_VYL,X
  LDA O_VYH,X
  SBC T1
  STA O_VYH,X
.ok_t:
  LDA GF
  AND #3
  BNE .ok_r
  DEC O_T,X
  BNE .ok_r
  JSR FREE
.ok_r:
  JMP OB_NEXT

; ---- enemy shot
OB_ESHOT:
  LDX SLOT
  JSR MOVE
  DEC O_T,X
  BNE .oe_r
  JSR FREE
.oe_r:
  JMP OB_NEXT

; ---- drone: 0 looks for a crystal or a rock, 1 mines the rock, 2 carries a crystal to the colossus
OB_DRONE:
  LDX SLOT
  JSR MOVE
  TXA                          ; decides every 8 frames
  CLC
  ADC GF
  AND #7
  BEQ .od_go
  JMP OB_NEXT
.od_go:
  LDA O_S,X
  CMP #1
  BEQ .od_mine
  BCC .od_seek
  JMP .od_carry
.od_seek:
  LDY O_C,X                    ; ---- 0: the target still there?
  BMI .od_pick
  LDA O_K,Y
  CMP #K_CRYS
  BEQ .od_to
  CMP #K_ROCK
  BEQ .od_to
.od_pick:
  JSR DRONE_TARGET
  LDY O_C,X
  BMI .od_stop
.od_to:
  JSR Q_OBJ
  JSR DIFF_Q
  JSR NEG_REL                  ; target - drone
  LDY O_C,X
  LDA O_K,Y
  CMP #K_CRYS
  BNE .od_rock
  LDA #8                       ; a crystal: take it
  JSR NEAR_REL
  BCS .od_fly
  LDA O_C,X
  TAY
  LDA #0
  STA O_K,Y
  STA O_V,Y
  LDA #2
  STA O_S,X
  BRA .od_stop
.od_rock:
  LDA #16                      ; a rock: mine it
  JSR NEAR_REL
  BCS .od_fly
  LDA #1
  STA O_S,X
  LDA DIFF
  ASL A
  ASL A
  STA T0
  LDA #150
  SEC
  SBC T0
  STA O_T,X
.od_stop:
  STZ O_VXL,X
  STZ O_VXH,X
  STZ O_VYL,X
  STZ O_VYH,X
  JMP OB_NEXT
.od_mine:
  LDA O_T,X                    ; ---- 1: mining
  SEC
  SBC #8
  STA O_T,X
  BCS .od_m
  LDA #2
  STA O_S,X
.od_m:
  JMP OB_NEXT
.od_carry:
  LDA NPIECE                   ; ---- 2: to the colossus (nothing missing: wait)
  CMP #NPIECES
  BEQ .od_stop
  JSR Q_COLOSSUS
  JSR DIFF_Q
  JSR NEG_REL
  LDA #24
  JSR NEAR_REL
  BCS .od_fly
  JSR ADD_PIECE
  LDX SLOT
  STZ O_S,X
  LDA #$FF
  STA O_C,X
  JMP OB_NEXT
.od_fly:
  JSR AIM
  STA DXT
  LDX SLOT
  LDY #2                       ; 1 pixel a frame, faster in later sectors
  LDA DIFF
  CMP #4
  BCC .od_sv
  INY
  CMP #8
  BCC .od_sv
  INY
.od_sv:
  LDA DXT
  JSR SET_VEL
  JMP OB_NEXT

; X = drone: a free crystal within 512 pixels, otherwise a rock at random (O_C, $FF = none)
DRONE_TARGET:
  LDA #$FF
  STA O_C,X
  LDY #G_CRYS
.dt_c:
  LDA O_K,Y
  CMP #K_CRYS
  BNE .dt_cn
  PHY
  JSR Q_OBJ
  JSR DIFF_Q
  PLY
  LDA RELX+1
  CLC
  ADC #2
  CMP #4
  BCS .dt_cn
  LDA RELY+1
  CLC
  ADC #2
  CMP #4
  BCS .dt_cn
  TYA
  STA O_C,X
  RTS
.dt_cn:
  INY
  CPY #G_BOOM
  BNE .dt_c
  JSR NEXT_RND                 ; a rock
  AND #15
  CLC
  ADC #G_ROCK
  TAY
  LDA #16
  STA T0
.dt_r:
  LDA O_K,Y
  CMP #K_ROCK
  BEQ .dt_ok
  INY
  CPY #G_DRONE
  BNE .dt_rn
  LDY #G_ROCK
.dt_rn:
  DEC T0
  BNE .dt_r
  RTS
.dt_ok:
  TYA
  STA O_C,X
  RTS

; ---- fighter: flies round the ship, shoots at it
OB_FIGHTER:
  LDX SLOT
  JSR MOVE
  DEC O_T,X                    ; time to shoot?
  BNE .of_st
  JSR NEXT_RND
  AND #31
  CLC
  ADC FTIME
  STA O_T,X
  LDA O_V,X
  BEQ .of_st
  LDA GSTATE
  BNE .of_st
  JSR FIGHTER_SHOT
.of_st:
  LDX SLOT
  TXA                          ; steers every 8 frames
  CLC
  ADC GF
  AND #7
  BNE .of_r
  JSR Q_SHIP                   ; target: the ship + 64 pixels in a turning direction
  TXA
  ASL A
  ASL A
  STA T0
  LDA GF+1
  ASL A
  ASL A
  ASL A
  ASL A
  STA T1
  LDA GF
  LSR A
  LSR A
  LSR A
  LSR A
  LSR A
  ORA T1
  CLC
  ADC T0
  AND #15
  TAY
  LDA ORBIT_X,Y
  BPL .of_xp
  DEC T5
.of_xp:
  CLC
  ADC T4
  STA T4
  BCC .of_xc
  INC T5
.of_xc:
  LDA T5
  AND #7
  STA T5
  LDA ORBIT_Y,Y
  BPL .of_yp
  DEC T7
.of_yp:
  CLC
  ADC T6
  STA T6
  BCC .of_yc
  INC T7
.of_yc:
  LDA T7
  BPL .of_y0
  LDA #5
.of_y0:
  CMP #6
  BCC .of_y1
  LDA #0
.of_y1:
  STA T7
  JSR DIFF_Q
  JSR NEG_REL
  LDA #6
  JSR NEAR_REL
  BCC .of_r
  JSR AIM
  LDX SLOT
  LDY #4                       ; 1.5 pixels a frame, 2 from sector 7
  STA T0
  LDA DIFF
  CMP #6
  BCC .of_v
  INY
.of_v:
  LDA T0
  JSR SET_VEL
.of_r:
  JMP OB_NEXT

; X = fighter: a shot at the ship
FIGHTER_SHOT:
  LDY #G_ESHOT
.fs_f:
  LDA O_K,Y
  BEQ .fs_go
  INY
  CPY #G_CRYS
  BNE .fs_f
  RTS
.fs_go:
  PHX
  JSR Q_SHIP
  JSR DIFF_Q
  JSR NEG_REL                  ; ship - fighter
  JSR AIM
  STA T0
  PLY                          ; Y = fighter
  LDX #G_ESHOT
.fs_s:
  LDA O_K,X
  BEQ .fs_k
  INX
  BRA .fs_s
.fs_k:
  LDA #K_ESHOT
  STA O_K,X
  JSR SPAWN_AT
  LDA #90
  STA O_T,X
  LDY #4                       ; 1.5 pixels a frame, 2 from sector 5
  LDA DIFF
  CMP #4
  BCC .fs_v
  INY
.fs_v:
  LDA T0
  JSR SET_VEL
  LDA #W_SHOT
  LDX #2
  JMP SFX_WHISTLE


; ===============================================================
;  HITS
; ===============================================================
; the shots against the rocks, drones and fighters on the screen (shots 1, 3 / 2, 4 in turn)
SHOT_HITS:
  LDA NVIS
  BEQ .sh_r
  LDA GF
  AND #1
  CLC
  ADC #G_SHOT
  TAX
.sh_s:
  LDA O_K,X
  CMP #K_SHOT
  BNE .sh_ns
  LDA O_V,X
  BEQ .sh_ns
  LDY #0
.sh_t:
  STY CNT
  LDA VLIST,Y
  TAY
  LDA O_K,Y                    ; (the target may have gone in this frame)
  CMP #K_ROCK
  BCC .sh_nt
  CMP #K_ESHOT
  BCS .sh_nt
  LDA O_SX,X
  SEC
  SBC O_SX,Y
  CLC
  ADC #9
  CMP #18
  BCS .sh_nt
  LDA O_SY,X
  SEC
  SBC O_SY,Y
  CLC
  ADC #9
  CMP #18
  BCS .sh_nt
  JSR FREE                     ; hit
  PHX
  TYA
  TAX
  JSR HIT_TARGET
  PLX
  BRA .sh_ns
.sh_nt:
  LDY CNT
  INY
  CPY NVIS
  BNE .sh_t
.sh_ns:
  INX
  INX
  CPX #G_CHARGE
  BCC .sh_s
.sh_r:
  RTS

; X = rock / drone / fighter hit by a shot
HIT_TARGET:
  LDA O_K,X
  CMP #K_ROCK
  BNE .ht_d
  LDA #S_DRILL                 ; rock: the drill, maybe a crystal
  LDX #2
  JSR SFX_BOOM
  TYA
  TAX
  JSR NEXT_RND
  CMP #90
  BCS .ht_nc
  JSR CRYSTAL_AT
.ht_nc:
  DEC O_H,X
  BNE .ht_r
  JSR BOOM_SLOT                  ; no ore left: it crumbles
  LDA #1
  STA ROCKD
  LDA #$50
  LDY #$00
  JSR ADD_PTS
  LDA #K_ROCK
  BRA .ht_gone
.ht_d:
  CMP #K_DRONE
  BNE .ht_f
  LDA O_S,X                    ; drone: drops what it carries
  CMP #2
  BNE .ht_dn
  JSR CRYSTAL_AT
.ht_dn:
  JSR BOOM_SLOT
  LDA #$50
  LDY #$01
  JSR ADD_PTS
  LDA #K_DRONE
  BRA .ht_gone
.ht_f:
  DEC O_H,X                    ; fighter: 2 hits
  BNE .ht_fh
  JSR BOOM_SLOT
  LDA #$00
  LDY #$05
  JSR ADD_PTS
  LDA #K_FIGHTER
.ht_gone:
  STA O_C,X                    ; it comes back later
  LDA #K_WAIT
  STA O_K,X
  STZ O_V,X
  LDA #WAIT_T
  STA O_T,X
  LDA #S_BOOM
  LDX #2
  JMP SFX_BOOM
.ht_fh:
  LDA #S_DRILL
  LDX #2
  JMP SFX_BOOM
.ht_r:
  RTS

; the ship against fighters, enemy shots and crystals on the screen
SHIP_HITS:
  LDA GSTATE
  BNE .sh2_r
  LDX #G_FIGHT
.sh2_l:
  LDA O_V,X
  BEQ .sh2_n
  LDA O_K,X
  CMP #K_FIGHTER
  BEQ .sh2_f
  CMP #K_ESHOT
  BEQ .sh2_e
  CMP #K_CRYS
  BNE .sh2_n
  LDA #11                      ; crystal: one charge more (at most 9), 200
  JSR NEAR_SHIP
  BCS .sh2_n
  JSR FREE
  LDA CHARGES
  CMP #9
  BCS .sh2_9
  INC CHARGES
.sh2_9:
  LDA #$00
  LDY #$02
  JSR ADD_PTS
  LDA #W_CRYS
  PHX
  LDX #2
  JSR SFX_WHISTLE
  PLX
  BRA .sh2_n
.sh2_f:
  LDA #10
  JSR NEAR_SHIP
  BCS .sh2_n
  LDA #2
  STA DEATH
  JMP SHIP_DIE
.sh2_e:
  LDA #6
  JSR NEAR_SHIP
  BCS .sh2_n
  JSR FREE
  LDA #3
  STA DEATH
  JMP SHIP_DIE
.sh2_n:
  INX
  CPX #G_BOOM
  BNE .sh2_l
.sh2_r:
  RTS

; X = slot on the screen: carry clear if its centre is within A pixels of the ship
NEAR_SHIP:
  STA T3
  ASL A
  STA T2
  LDA O_SX,X
  SEC
  SBC #HX_SCR
  CLC
  ADC T3
  CMP T2
  BCS .ns_r
  LDA O_SY,X
  SEC
  SBC #HY_SCR
  CLC
  ADC T3
  CMP T2
.ns_r:
  RTS


; ===============================================================
;  SPRITES: ship, eyes, radar marks, then the objects in turn
; ===============================================================
BUILD_SAT:
  STZ SPRI
  LDA GSTATE                   ; the ship (not when lost)
  CMP #1
  BEQ .bs_e
  LDA #HX_SCR
  STA OX
  LDA #HY_SCR+8
  STA OY
  LDA HDIR
  ASL A
  ASL A
  STA ON
  LDA #$0B
  STA OC
  JSR ADD_SPR
.bs_e:
  LDA EYEV                     ; the eyes of the colossus
  BEQ .bs_m
  LDX SPRI
  LDA EYEY
  DEC A
  STA SAT_BUFFER,X
  LDA EYEX
  STA SAT_BUFFER+1,X
  LDA #PT_EYES
  STA SAT_BUFFER+2,X
  LDA #$08
  STA SAT_BUFFER+3,X
  TXA
  CLC
  ADC #4
  STA SPRI
.bs_m:
  LDX #0                       ; radar: the ship
  JSR RADAR_XY
  LDX SPRI
  LDA T1
  DEC A
  STA SAT_BUFFER,X
  LDA T0
  CLC
  ADC #112
  STA SAT_BUFFER+1,X
  LDA #PT_MARK1
  STA SAT_BUFFER+2,X
  LDA #$0B
  STA SAT_BUFFER+3,X
  TXA
  CLC
  ADC #4
  STA SPRI
  LDA NPIECE                   ; radar: the colossus
  BEQ .bs_o
  LDA CXL
  STA T4
  LDA CXH
  STA T5
  LDA CYL
  STA T6
  LDA CYH
  STA T7
  LDA T4
  ROL A
  ROL A
  ROL A
  AND #3
  STA T0
  LDA T5
  ASL A
  ASL A
  ORA T0
  CLC
  ADC #111
  STA T0
  LDA T6
  ROL A
  ROL A
  ROL A
  AND #3
  STA T1
  LDA T7
  ASL A
  ASL A
  ORA T1
  SEC
  SBC #2
  BPL .bs_cy
  LDA #$FF
.bs_cy:
  LDX SPRI
  STA SAT_BUFFER,X
  LDA T0
  STA SAT_BUFFER+1,X
  LDA #PT_MARK2
  STA SAT_BUFFER+2,X
  LDA #$08
  STA SAT_BUFFER+3,X
  TXA
  CLC
  ADC #4
  STA SPRI
.bs_o:
  LDA NSL                      ; the objects on the screen, from number RR on
  BEQ .bs_end
  STA CNT
  LDY RR
  CPY NSL
  BCC .bs_l
  LDY #0
.bs_l:
  LDX SLIST,Y
  LDA O_SX,X
  STA OX
  LDA O_SY,X
  CLC
  ADC #8
  STA OY
  LDA O_K,X
  STA T0
  PHY
  LDY T0
  LDA KPAT,Y
  STA ON
  LDA KCOL,Y
  STA OC
  LDA KANIM,Y                  ; second pattern: 1 = every 8 frames, 2 = odd slots
  BEQ .bs_a
  CMP #2
  BEQ .bs_sl
  LDA GF
  AND #8
  BEQ .bs_a
  BRA .bs_p4
.bs_sl:
  TXA
  AND #1
  BEQ .bs_a
.bs_p4:
  LDA ON
  CLC
  ADC #4
  STA ON
.bs_a:
  CPY #K_DRONE                 ; a drone with a crystal: cyan
  BNE .bs_add
  LDA O_S,X
  CMP #2
  BNE .bs_add
  LDA #$07
  STA OC
.bs_add:
  JSR ADD_SPR
  PLY
  INY
  CPY NSL
  BCC .bs_w
  LDY #0
.bs_w:
  DEC CNT
  BNE .bs_l
  INY                          ; next frame: start 3 sprites later
  INY
  STY RR
.bs_end:
  LDX SPRI
  LDA #$D0
  STA SAT_BUFFER,X
  INX
  STX SATB
  RTS


; ===============================================================
;  SCREEN: VRAM, texts, sprites, sound (from core runner)
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

; the table GFX_LOAD (font, small tiles) then the sprites
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
; a 16x16 sprite with the feet at (OX, OY): x = OX - 8, last line = OY - 1; pattern ON, colour OC
ADD_SPR:
  LDX SPRI
  CPX #128
  BCS .as_r
  LDA OY
  SEC
  SBC #17
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
;  REC_SIGN: the sign screen. UP / DOWN change the letter,
;  LEFT / RIGHT move, a button moves on (on the third letter it
;  confirms); after 30 s without a key it confirms by itself.
; ---------------------------------------------------------------
REC_SIGN:
  JSR VDP_INT_OFF
  JSR HIDE_SPRITES               ; nothing of the game over the table
  JSR REC_CLS
  LDX #REC_SROW-4
  LDY #11
  LDA #(RT_NEW-REC_TXT)
  JSR REC_PUTS
  LDX #REC_SROW-2
  LDY #12
  LDA #(RT_PLAYER-REC_TXT)
  JSR REC_PUTS
  LDA REC_PL
  CLC
  ADC #'1'
  STA VDATA
  LDA #REC_SROW
  STA REC_R0
  JSR REC_SHOW_R
  LDX #REC_SROW+10
  LDY #7
  LDA #(RT_H1-REC_TXT)
  JSR REC_PUTS
  LDX #REC_SROW+11
  LDY #7
  LDA #(RT_H2-REC_TXT)
  JSR REC_PUTS
  LDX #REC_SROW+12
  LDY #7
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
  STA VDATA
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
  STA VDATA
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
  STA VDATA
  RTS

; REC_WIPEN rows from REC_ROW blank (REC_WIPE_R: from REC_R0)
REC_WIPE:
  LDA #REC_ROW
  STA REC_R0
REC_WIPE_R:
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
  STA VDATA
  INX
  BRA .pu_l
.pu_e:
  RTS

REC_TXT:
RT_NEW:    .byte "NEW RECORD",0
RT_PLAYER: .byte "PLAYER ",0
RT_H1:     .byte "UP/DOWN    LETTER",0
RT_H2:     .byte "LEFT/RIGHT MOVE",0
RT_H3:     .byte "BUTTON     NEXT/OK",0
; ===============================================================
;  TABLES
; ===============================================================
SC_COL:     .byte 4,24                         ; score of player 1 / 2: column on row 0
BITS:       .byte 1,2,4,8,16,32,64,128
BITR:       .byte 128,64,32,16,8,4,2,1
; joystick bits (up 1, down 2, left 4, right 8) -> direction 0-7, $FF = none
JOYDIR:     .byte $FF,0,4,$FF, 6,7,5,6, 2,1,3,2, $FF,0,4,$FF
; objects: routine, pattern, colour, animation (1 = every 8 frames, 2 = odd slots) per kind
OBJ_JT:     .word OB_NONE, OB_NONE, OB_SHOT, OB_CHARGE, OB_ROCK, OB_DRONE, OB_FIGHTER, OB_ESHOT, OB_CRYS, OB_BOOM, OB_WAIT
KPAT:       .byte 0, PT_SHIP, PT_SHOT, PT_CHARGE, PT_ROCK, PT_DRONE, PT_FIGHTER, PT_ESHOT, PT_CRYS, PT_BOOM, 0
KCOL:       .byte 0, $0B, $0F, $0D, $0A, $02, $08, $09, $07, $0B, 0
KANIM:      .byte 0, 0, 0, 1, 2, 1, 1, 0, 1, 1, 0

; the picture of the colossus: column offsets, first tile code of every column, frames
COL_OFS:    .byte <8, <(CLEN+8), <(2*CLEN+8), <(3*CLEN+8), <(4*CLEN+8), <(5*CLEN+8), <(6*CLEN+8)
COL_OFH:    .byte >8, >(CLEN+8), >(2*CLEN+8), >(3*CLEN+8), >(4*CLEN+8), >(5*CLEN+8), >(6*CLEN+8)
COL_CODE:   .byte 0, 6, 12, 18, 24, 30, 36
FRAME_LO:   .byte <(0*FRAME_LEN), <(1*FRAME_LEN), <(2*FRAME_LEN), <(3*FRAME_LEN)
            .byte <(4*FRAME_LEN), <(5*FRAME_LEN), <(6*FRAME_LEN), <(7*FRAME_LEN)
FRAME_HI:   .byte >(0*FRAME_LEN), >(1*FRAME_LEN), >(2*FRAME_LEN), >(3*FRAME_LEN)
            .byte >(4*FRAME_LEN), >(5*FRAME_LEN), >(6*FRAME_LEN), >(7*FRAME_LEN)

; title: ship, crystal, drone, fighter, rock, charge  (sprite Y, X, pattern, colour)
TITLE_SY:   .byte 9*8-5,11*8-5,13*8-5,15*8-5,17*8-5,19*8-5
TITLE_SX:   .byte 40,40,40,40,40,40
TITLE_SN:   .byte PT_SHIP,PT_CRYS,PT_DRONE,PT_FIGHTER,PT_ROCK,PT_CHARGE
TITLE_SC:   .byte $0B,$07,$02,$08,$0A,$0D

MSG_LO:     .byte <MSG0,<MSG1,<MSG2,<MSG3
MSG_HI:     .byte >MSG0,>MSG1,>MSG2,>MSG3

; text records: row, column, characters, 0   (end of list: $FF)
TXT_TOP:
  .byte 0,0,"1UP",0
  .byte 1,0,"HI",0
  .byte $FF
TXT_SEC:
  .byte "SECTOR ",0
TXT_COL:
  .byte "PIECES ",0
TXT_TITLE:
  .byte 9,8,"MINER    B1 = CANNON",0
  .byte 11,8,"CRYSTAL          200",0
  .byte 13,8,"DRONE            150",0
  .byte 15,8,"FIGHTER          500",0
  .byte 17,8,"ROCK              50",0
  .byte 19,8,"CHARGE   B2 = DROP",0
  .byte 21,2,"BLOW UP THE COLOSSUS  15000",0
  .byte 22,1,"B1 = 1 PLAYER   B2 = 2 PLAYERS",0
  .byte 23,3,"DEVELOPED BY BOOGS & CCAI",0
  .byte $FF
TXT_PLAYER:
  .byte 7,12,"PLAYER ",0
  .byte $FF
TXT_SECTOR:
  .byte 10,11,"SECTOR ",0
  .byte $FF
TXT_CLEAR:
  .byte 9,3,"THE COLOSSUS IS DESTROYED",0
  .byte $FF
TXT_BONUS:
  .byte 12,10,"BONUS ",0
  .byte $FF
TXT_OVER:
  .byte 11,11,"GAME OVER",0
  .byte $FF
TXT_H0:
  .byte 14,2,"SHOOT THE ROCKS FOR CRYSTALS",0
  .byte 16,1,"A CRYSTAL IS A SEISMIC CHARGE",0
  .byte 18,3,"DRONES BUILD THE COLOSSUS",0
  .byte 20,3,"BLOW IT UP PIECE BY PIECE",0
  .byte $FF
TXT_H1:
  .byte 15,4,"THE DRONES ARE BUILDING",0
  .byte 17,7,"FIND THE CRYSTALS",0
  .byte $FF
TXT_H2:
  .byte 15,7,"A SWARM OF DRONES",0
  .byte 17,3,"THE COLOSSUS IS HALF BUILT",0
  .byte $FF
MSG0:
  .byte 23,6,"THE COLOSSUS AWAKES",0
  .byte $FF
MSG1:
  .byte 23,10,"IT IS COMING",0
  .byte $FF
MSG2:
  .byte 23,11,"NO WAY OUT",0
  .byte $FF
MSG3:
  .byte 23,9,"PIECE BY PIECE",0
  .byte $FF

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

; song * 4 + track
SONGP_LO:      .byte <M0_LEAD,<M0_HARM,<M0_BASS,<M0_DRUM, <M1_LEAD,<M1_HARM,<M1_BASS,<M1_DRUM, <M2_LEAD,<M2_HARM,<M2_BASS,<M2_DRUM
SONGP_HI:      .byte >M0_LEAD,>M0_HARM,>M0_BASS,>M0_DRUM, >M1_LEAD,>M1_HARM,>M1_BASS,>M1_DRUM, >M2_LEAD,>M2_HARM,>M2_BASS,>M2_DRUM

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

; three tunes composed for this game
;   C2 1 D2 3 E2 5 F2 6 G2 8 A2 10 C3 13 D3 15 E3 17 F3 18 G3 20 A3 22 Bb3 23 C4 25 D4 27 E4 29
;   F4 30 G4 32 A4 34 Bb4 35 C5 37 D5 39 E5 41 F5 42 F#5 43 G5 44 A5 46 B5 48 C6 49 D6 51 F#6 55
; a new sector: D minor over a hammering bass (3 seconds)
M0_LEAD:
  .byte 27,6, 30,6, 34,12, 32,6, 30,6, 29,12, 27,6, 29,6, 30,6, 32,6, 34,24
  .byte 0,6, 39,12, 37,6, 34,6, 35,12, 34,36
  .byte $FF
M0_HARM:
  .byte 22,48, 23,48, 20,48, 22,36
  .byte $FF
M0_BASS:
  .byte 3,6, 3,6, 15,6, 3,6, 3,6, 3,6, 15,6, 3,6, 3,6, 3,6, 15,6, 3,6, 3,6, 3,6, 15,6, 3,6
  .byte 6,6, 6,6, 18,6, 6,6, 10,6, 10,6, 22,6, 10,6, 3,36
  .byte $FF
M0_DRUM:
  .byte 1,6, 3,6, 2,6, 3,6, 1,6, 3,6, 2,6, 3,6, 1,6, 3,6, 2,6, 3,6, 1,6, 3,6, 2,6, 3,6
  .byte 1,6, 3,6, 2,6, 3,6, 1,6, 3,6, 2,6, 3,6, 1,6, 3,6, 2,6, 3,6, 4,12
  .byte $FF
; the colossus destroyed: a bright fanfare in D (1.4 seconds)
M1_LEAD:
  .byte 39,6, 43,6, 46,6, 51,18, 0,6, 49,6, 51,6, 55,30
  .byte $FF
M1_HARM:
  .byte 34,24, 37,24, 39,36
  .byte $FF
M1_BASS:
  .byte 15,24, 10,24, 3,36
  .byte $FF
M1_DRUM:
  .byte 2,6, 2,6, 2,6, 1,18, 3,6, 3,6, 1,12, 4,24
  .byte $FF
; title: A minor, slow and heavy (3.6 seconds)
M2_LEAD:
  .byte 34,12, 37,12, 41,24, 39,12, 37,12, 34,24, 32,12, 34,12, 37,12, 32,12, 29,48
  .byte $FF
M2_HARM:
  .byte 25,48, 29,48, 27,48, 25,72
  .byte $FF
M2_BASS:
  .byte 10,24, 10,24, 6,24, 6,24, 8,24, 8,24, 10,72
  .byte $FF
M2_DRUM:
  .byte 1,12, 3,12, 2,12, 3,12, 1,12, 3,12, 2,12, 3,12, 1,12, 3,12, 2,12, 3,12, 1,12, 3,12, 2,12, 3,12, 4,24
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
; Deep Space Miner: generated by dev/gen_deep_space_miner.js (do not edit by hand)

; sprite patterns (16x16), value = pattern number * 4
PT_SHIP = 0
PT_SHOT = 32
PT_ESHOT = 36
PT_CHARGE = 40
PT_ROCK = 48
PT_CRYS = 56
PT_DRONE = 64
PT_FIGHTER = 72
PT_BOOM = 80
PT_EYES = 88
PT_MARK1 = 92
PT_MARK2 = 96
SPR_PAGES = 4
SPRITES:
  .byte $01,$01,$01,$01,$01,$01,$03,$02,$06,$07,$7F,$FF,$E7,$E3,$40,$00
  .byte $80,$80,$80,$80,$80,$80,$C0,$40,$60,$E0,$FE,$FF,$E7,$C7,$02,$00
  .byte $00,$00,$00,$00,$00,$C0,$E7,$FE,$1E,$1F,$3F,$1F,$0F,$04,$00,$00
  .byte $00,$00,$08,$1C,$38,$70,$E0,$40,$40,$C0,$C0,$80,$80,$C0,$E0,$E0
  .byte $38,$7C,$3C,$0C,$0C,$1F,$3F,$3E,$3E,$3F,$1F,$0C,$0C,$3C,$7C,$38
  .byte $00,$00,$00,$00,$00,$00,$C0,$7F,$7F,$C0,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$04,$0F,$1F,$3F,$1F,$1E,$FE,$E7,$C0,$00,$00,$00,$00,$00
  .byte $E0,$E0,$C0,$80,$80,$C0,$C0,$40,$40,$E0,$70,$38,$1C,$08,$00,$00
  .byte $00,$40,$E3,$E7,$FF,$7F,$07,$06,$02,$03,$01,$01,$01,$01,$01,$01
  .byte $00,$02,$C7,$E7,$FF,$FE,$E0,$60,$40,$C0,$80,$80,$80,$80,$80,$80
  .byte $07,$07,$03,$01,$01,$03,$03,$02,$02,$07,$0E,$1C,$38,$10,$00,$00
  .byte $00,$00,$20,$F0,$F8,$FC,$F8,$78,$7F,$E7,$03,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$03,$FE,$FE,$03,$00,$00,$00,$00,$00,$00
  .byte $1C,$3E,$3C,$30,$30,$F8,$FC,$7C,$7C,$FC,$F8,$30,$30,$3C,$3E,$1C
  .byte $00,$00,$10,$38,$1C,$0E,$07,$02,$02,$03,$03,$01,$01,$03,$07,$07
  .byte $00,$00,$00,$00,$00,$03,$E7,$7F,$78,$F8,$FC,$F8,$F0,$20,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$01,$01,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$80,$80,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$02,$01,$01,$02,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$40,$80,$80,$40,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$01,$03,$06,$0C,$06,$03,$01,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$80,$C0,$60,$C0,$80,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$08,$05,$03,$0E,$03,$05,$08,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$20,$40,$80,$E0,$80,$40,$20,$00,$00,$00,$00,$00,$00
  .byte $00,$01,$03,$07,$1F,$31,$71,$71,$7F,$7F,$3F,$1E,$0F,$07,$00,$00
  .byte $00,$C0,$F0,$F8,$FC,$FC,$FC,$FC,$FC,$8C,$8C,$FC,$FC,$F8,$00,$00
  .byte $00,$00,$01,$03,$1F,$31,$31,$31,$3F,$3F,$1F,$0E,$07,$00,$00,$00
  .byte $00,$00,$E0,$F0,$F8,$F8,$FC,$FC,$F8,$88,$88,$F8,$F0,$F0,$00,$00
  .byte $00,$00,$00,$00,$01,$03,$07,$0E,$07,$03,$01,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$80,$C0,$E0,$C0,$80,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$01,$01,$03,$0F,$03,$01,$01,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$80,$E0,$80,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$10,$08,$07,$0D,$0F,$0D,$07,$08,$10,$00,$00,$00,$00
  .byte $00,$00,$00,$08,$10,$E0,$B0,$F0,$B0,$E0,$10,$08,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$30,$0F,$0D,$0F,$0D,$0F,$30,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$0C,$F0,$B0,$F0,$B0,$F0,$0C,$00,$00,$00,$00,$00
  .byte $00,$00,$01,$03,$83,$C7,$EF,$FF,$F6,$E1,$C0,$80,$00,$00,$00,$00
  .byte $00,$00,$80,$C0,$C1,$E3,$F7,$FF,$6F,$87,$03,$01,$00,$00,$00,$00
  .byte $00,$00,$01,$03,$03,$47,$EF,$FF,$F6,$61,$40,$00,$00,$00,$00,$00
  .byte $00,$00,$80,$C0,$C0,$E2,$F7,$FF,$6F,$86,$02,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$01,$0D,$0F,$06,$1C,$1C,$06,$0F,$0D,$01,$00,$00,$00
  .byte $00,$00,$00,$80,$B0,$F0,$60,$38,$38,$60,$F0,$B0,$80,$00,$00,$00
  .byte $00,$06,$07,$37,$3F,$3E,$1C,$78,$78,$1C,$3E,$3F,$37,$07,$06,$00
  .byte $00,$60,$E0,$EC,$FC,$7C,$38,$1E,$1E,$38,$7C,$FC,$EC,$E0,$60,$00
  .byte $00,$00,$00,$00,$00,$00,$03,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$30,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $C0,$C0,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $E0,$E0,$E0,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00

T_FAR = 1
T_LIFE = 17
T_CHG = 18
T_NEAR = 96
T_RADAR = 160
T_COLA = 172
T_COLB = 214
FAR_PAT:
  .byte $80,$00,$00,$00,$00,$00,$00,$00,$20,$00,$00,$00,$00,$00,$00,$00
  .byte $08,$00,$00,$00,$00,$00,$00,$00,$02,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$80,$00,$00,$00,$00,$00,$00,$00,$20,$00,$00,$00,$00,$00
  .byte $00,$00,$08,$00,$00,$00,$00,$00,$00,$00,$02,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$80,$00,$00,$00,$00,$00,$00,$00,$20,$00,$00,$00
  .byte $00,$00,$00,$00,$08,$00,$00,$00,$00,$00,$00,$00,$02,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$80,$00,$00,$00,$00,$00,$00,$00,$20,$00
  .byte $00,$00,$00,$00,$00,$00,$08,$00,$00,$00,$00,$00,$00,$00,$02,$00
NEAR_PAT:
  .byte $80,$00,$00,$00,$00,$00,$00,$00,$40,$00,$00,$00,$00,$00,$00,$00
  .byte $20,$00,$00,$00,$00,$00,$00,$00,$10,$00,$00,$00,$00,$00,$00,$00
  .byte $08,$00,$00,$00,$00,$00,$00,$00,$04,$00,$00,$00,$00,$00,$00,$00
  .byte $02,$00,$00,$00,$00,$00,$00,$00,$01,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$80,$00,$00,$00,$00,$00,$00,$00,$40,$00,$00,$00,$00,$00,$00
  .byte $00,$20,$00,$00,$00,$00,$00,$00,$00,$10,$00,$00,$00,$00,$00,$00
  .byte $00,$08,$00,$00,$00,$00,$00,$00,$00,$04,$00,$00,$00,$00,$00,$00
  .byte $00,$02,$00,$00,$00,$00,$00,$00,$00,$01,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$80,$00,$00,$00,$00,$00,$00,$00,$40,$00,$00,$00,$00,$00
  .byte $00,$00,$20,$00,$00,$00,$00,$00,$00,$00,$10,$00,$00,$00,$00,$00
  .byte $00,$00,$08,$00,$00,$00,$00,$00,$00,$00,$04,$00,$00,$00,$00,$00
  .byte $00,$00,$02,$00,$00,$00,$00,$00,$00,$00,$01,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$80,$00,$00,$00,$00,$00,$00,$00,$40,$00,$00,$00,$00
  .byte $00,$00,$00,$20,$00,$00,$00,$00,$00,$00,$00,$10,$00,$00,$00,$00
  .byte $00,$00,$00,$08,$00,$00,$00,$00,$00,$00,$00,$04,$00,$00,$00,$00
  .byte $00,$00,$00,$02,$00,$00,$00,$00,$00,$00,$00,$01,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$80,$00,$00,$00,$00,$00,$00,$00,$40,$00,$00,$00
  .byte $00,$00,$00,$00,$20,$00,$00,$00,$00,$00,$00,$00,$10,$00,$00,$00
  .byte $00,$00,$00,$00,$08,$00,$00,$00,$00,$00,$00,$00,$04,$00,$00,$00
  .byte $00,$00,$00,$00,$02,$00,$00,$00,$00,$00,$00,$00,$01,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$80,$00,$00,$00,$00,$00,$00,$00,$40,$00,$00
  .byte $00,$00,$00,$00,$00,$20,$00,$00,$00,$00,$00,$00,$00,$10,$00,$00
  .byte $00,$00,$00,$00,$00,$08,$00,$00,$00,$00,$00,$00,$00,$04,$00,$00
  .byte $00,$00,$00,$00,$00,$02,$00,$00,$00,$00,$00,$00,$00,$01,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$80,$00,$00,$00,$00,$00,$00,$00,$40,$00
  .byte $00,$00,$00,$00,$00,$00,$20,$00,$00,$00,$00,$00,$00,$00,$10,$00
  .byte $00,$00,$00,$00,$00,$00,$08,$00,$00,$00,$00,$00,$00,$00,$04,$00
  .byte $00,$00,$00,$00,$00,$00,$02,$00,$00,$00,$00,$00,$00,$00,$01,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$80,$00,$00,$00,$00,$00,$00,$00,$40
  .byte $00,$00,$00,$00,$00,$00,$00,$20,$00,$00,$00,$00,$00,$00,$00,$10
  .byte $00,$00,$00,$00,$00,$00,$00,$08,$00,$00,$00,$00,$00,$00,$00,$04
  .byte $00,$00,$00,$00,$00,$00,$00,$02,$00,$00,$00,$00,$00,$00,$00,$01
ICON_PAT:
  .byte $18,$18,$3C,$66,$FF,$FF,$DB,$42,$10,$38,$7C,$FE,$7C,$38,$10,$00
ICON_COL:
  .byte $B0,$B0,$B0,$B0,$B0,$B0,$B0,$B0,$70,$70,$70,$70,$70,$70,$70,$70

; the colossus: (walk frame * 4 + shift) * FRAME_LEN + column * CLEN + 8 + row
NPIECES = 20
COLS = 7
CLEN = 56
FRAME_LEN = 392
; pieces in VRAM tile row r of column c (index c x 6 + r, + 42 when the row offset is not 0)
CM0:
  .byte $20,$80,$80,$00,$00,$00,$30,$D0,$80,$00,$00,$00,$1C,$56,$03,$01,$01,$00,$0C,$06,$03
  .byte $01,$01,$00,$0C,$06,$03,$01,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $20,$A0,$80,$00,$00,$00,$30,$F0,$D0,$00,$00,$00,$1C,$5E,$57,$03,$01,$01,$0C,$0E,$07
  .byte $03,$01,$01,$0C,$0E,$03,$03,$01,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
CM1:
  .byte $00,$00,$02,$02,$08,$00,$00,$00,$03,$0E,$0C,$00,$00,$00,$01,$04,$00,$00,$00,$10,$00
  .byte $00,$00,$00,$10,$50,$00,$00,$00,$00,$30,$D0,$80,$00,$00,$00,$20,$80,$80,$00,$00,$00
  .byte $00,$00,$02,$02,$0A,$08,$00,$00,$03,$0F,$0E,$08,$00,$00,$01,$05,$04,$00,$00,$10,$10
  .byte $00,$00,$00,$10,$50,$50,$00,$00,$00,$30,$F0,$D0,$00,$00,$00,$20,$A0,$80,$00,$00,$00
CM2:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$05,$04,$04,$00,$00,$00,$03,$0E,$0C,$00,$00,$00,$02,$02,$08,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$05,$05,$04,$00,$00,$00,$03,$0F,$0E,$08,$00,$00,$02,$02,$0A,$08
BUILD_ORDER:
  .byte $00,$01,$02,$03,$04,$0C,$05,$0D,$06,$0E,$07,$0F,$08,$10,$09,$11,$0A,$12,$0B,$13
CO_BMP:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$18,$0E,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$0E,$30,$10,$00,$00,$00
  .byte $00,$00,$03,$0E,$18,$08,$00,$00,$00,$00,$00,$00,$00,$00,$01,$03,$06,$0C,$18,$30,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$E0,$78,$3C,$1E,$0F,$07,$03,$00,$00,$20,$7C,$FF,$07,$00,$00,$00,$01,$2F
  .byte $3F,$F8,$00,$00,$00,$01,$03,$07,$0E,$0C,$38,$30,$60,$C0,$80,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$18,$18,$08,$0C,$07,$0F,$0D,$8F,$CF,$E7,$7F,$38,$37,$EF,$FF,$7F,$2F,$3F,$F7,$FF
  .byte $1F,$3F,$7F,$7F,$C1,$FE,$FC,$FC,$FC,$04,$FE,$7F,$7F,$7F,$00,$1F,$0F,$03,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$0C,$04,$08,$08,$F0,$F0,$D0,$F0,$F0,$E0,$F3,$1F,$EE,$F5,$F7,$F6,$F4,$F7,$EF,$FB
  .byte $FE,$FF,$FF,$FF,$80,$7F,$3F,$3F,$3F,$20,$7F,$FE,$FE,$FE,$00,$F8,$F0,$C0,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$03,$0E,$1C,$78,$E1,$C7,$1E,$7C,$F0,$80,$00,$00,$00,$C0,$E0
  .byte $F8,$3F,$8F,$C3,$E0,$70,$38,$1C,$0F,$07,$03,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$1E,$E4,$00,$00,$00,$00,$C0,$3C,$08,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$80,$C0,$30,$18,$0C,$02,$04,$80,$C0,$60,$10,$08,$04,$08,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$06,$03,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$03,$0C,$04,$00,$00,$00
  .byte $00,$00,$00,$03,$06,$02,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$03,$06,$0C,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$80,$78,$1E,$0F,$07,$03,$01,$00,$00,$00,$08,$1F,$7F,$81,$00,$00,$00,$00,$0B
  .byte $0F,$3E,$C0,$80,$00,$00,$00,$01,$03,$03,$0E,$0C,$18,$30,$60,$C0,$80,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$06,$06,$02,$03,$01,$83,$C3,$E3,$F3,$39,$1F,$0E,$0D,$FB,$FF,$1F,$0B,$0F,$7D,$FF
  .byte $C7,$0F,$1F,$1F,$30,$7F,$FF,$FF,$BF,$01,$3F,$1F,$1F,$1F,$00,$07,$03,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$03,$01,$02,$02,$FC,$FC,$74,$FC,$FC,$F8,$FC,$07,$FB,$FD,$FD,$FD,$FD,$FD,$FB,$FE
  .byte $FF,$FF,$FF,$FF,$60,$9F,$0F,$0F,$0F,$08,$9F,$FF,$FF,$FF,$00,$FE,$FC,$F0,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$03,$07,$1E,$38,$F1,$C7,$9F,$7C,$E0,$80,$00,$C0,$F0,$F8
  .byte $BE,$CF,$E3,$F0,$38,$DC,$CE,$C7,$C3,$01,$C0,$80,$80,$80,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$47,$F9,$80,$00,$00,$40,$F0,$8F,$02,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$C0,$C0,$E0,$30,$0C,$06,$03,$C0,$C1,$E0,$30,$18,$04,$02,$01,$02,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$80,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$80,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$03,$01,$00,$00,$00
  .byte $00,$00,$00,$00,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$03,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$80,$E0,$1E,$07,$03,$01,$00,$00,$00,$00,$00,$02,$07,$1F,$E0,$00,$00,$00,$00,$02
  .byte $03,$0F,$30,$E0,$80,$80,$00,$00,$00,$00,$03,$03,$06,$0C,$18,$30,$60,$C0,$80,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$01,$01,$00,$80,$C0,$E0,$F0,$78,$3C,$0E,$07,$03,$C3,$FE,$7F,$07,$02,$03,$1F,$FF
  .byte $F1,$83,$07,$07,$0C,$1F,$3F,$7F,$EF,$C0,$8F,$07,$07,$07,$00,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$80,$80,$80,$C0,$7F,$FF,$DD,$FF,$FF,$7E,$FF,$81,$7E,$FF,$FF,$FF,$FF,$FF,$7E,$FF
  .byte $FF,$FF,$FF,$FF,$18,$E7,$C3,$C3,$C3,$42,$E7,$FF,$FF,$FF,$00,$FF,$FF,$3C,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$C0,$40,$80,$80,$00,$00,$00,$01,$07,$0E,$3C,$F1,$E7,$5F,$78,$60,$40,$70,$FC,$BE
  .byte $EF,$F3,$F8,$FC,$0E,$F7,$F3,$F1,$F0,$00,$F0,$E0,$E0,$E0,$00,$80,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$11,$3E,$E0,$C0,$80,$10,$7C,$E3,$C0,$00,$00,$00,$00,$00,$00,$00
  .byte $80,$F0,$F0,$38,$0C,$03,$81,$C0,$F0,$70,$38,$0C,$06,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$E0,$40,$00,$00,$00,$00,$00,$C0,$80,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$80,$C0,$20,$40,$00,$00,$00,$00,$80,$40,$80,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$60,$38,$07,$01,$00,$00,$00,$00,$00,$00,$00,$00,$01,$07,$38,$C0,$40,$00,$00,$00
  .byte $00,$03,$0C,$38,$60,$20,$00,$00,$00,$00,$00,$00,$01,$03,$06,$0C,$18,$30,$60,$C0,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$80,$E0,$F0,$78,$3C,$1E,$0F,$03,$01,$80,$F0,$FF,$1F,$01,$00,$00,$07,$BF
  .byte $FC,$E0,$01,$01,$03,$07,$0F,$1F,$3B,$30,$E3,$C1,$81,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$60,$60,$20,$30,$1F,$3F,$37,$3F,$3F,$9F,$FF,$E0,$DF,$BF,$FF,$FF,$BF,$FF,$DF,$FF
  .byte $7F,$FF,$FF,$FF,$06,$F9,$F0,$F0,$F0,$10,$F9,$FF,$FF,$FF,$00,$7F,$3F,$0F,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$30,$10,$20,$20,$C0,$C0,$40,$C0,$C1,$83,$CF,$7C,$B9,$D7,$DE,$D8,$D0,$DC,$BF,$EF
  .byte $FB,$FC,$FE,$FF,$03,$FD,$FC,$FC,$FC,$80,$FC,$F8,$F8,$F8,$00,$E0,$C0,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$04,$0F,$38,$70,$E0,$84,$1F,$78,$F0,$C0,$00,$00,$00,$00,$00,$80
  .byte $E0,$FC,$3C,$0E,$83,$C0,$E0,$70,$3C,$1C,$0E,$03,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$78,$90,$00,$00,$00,$00,$00,$F0,$20,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$C0,$60,$30,$08,$10,$00,$00,$80,$40,$20,$10,$20,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$3E,$13,$00,$00,$00,$00,$01,$1F,$08,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$01,$03,$04,$18,$30,$10,$00,$00,$03,$06,$0C,$18,$08,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$20,$F8,$3C,$1F,$07,$23,$F8,$3E,$0F,$03,$00,$00,$00,$00,$00,$01
  .byte $07,$3F,$3C,$70,$81,$03,$07,$0E,$3C,$38,$70,$80,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$18,$18,$08,$0C,$07,$0F,$0D,$0F,$8F,$E7,$FF,$78,$F7,$FF,$FF,$7F,$2F,$3F,$77,$FF
  .byte $9F,$3F,$7F,$FF,$C1,$FE,$FC,$FC,$FC,$04,$FE,$7F,$7F,$7F,$00,$1F,$0F,$03,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$0C,$04,$08,$08,$F0,$F0,$D0,$F0,$F0,$E1,$F3,$1F,$EE,$F4,$F7,$F7,$F4,$F7,$EF,$F9
  .byte $FE,$FF,$FF,$FF,$81,$7F,$3F,$3F,$3F,$20,$7F,$FE,$FE,$FE,$00,$F8,$F0,$C0,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$03,$06,$0C,$18,$70,$E0,$C0,$80,$01,$0F,$FE,$F8,$00,$00,$00,$E0,$FD
  .byte $3F,$07,$80,$80,$C0,$E0,$70,$38,$3C,$1C,$0F,$07,$03,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$0C,$38,$E0,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$E0,$3C,$06,$04,$00,$00,$00
  .byte $00,$C0,$60,$18,$04,$08,$00,$00,$00,$00,$00,$00,$00,$80,$40,$20,$10,$08,$04,$02,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$0F,$04,$00,$00,$00,$00,$00,$07,$02,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$01,$06,$0C,$04,$00,$00,$00,$01,$03,$06,$02,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$88,$FE,$0F,$07,$01,$08,$7E,$CF,$03,$00,$00,$00,$00,$00,$00,$00
  .byte $01,$0F,$0F,$1C,$60,$C0,$01,$03,$0F,$0E,$1C,$20,$C0,$80,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$06,$06,$02,$03,$01,$03,$03,$C3,$E3,$F9,$3F,$9E,$FD,$FF,$3F,$1F,$0B,$0F,$1D,$7F
  .byte $E7,$CF,$1F,$3F,$70,$FF,$FF,$BF,$3F,$01,$3F,$1F,$1F,$1F,$00,$07,$03,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$03,$01,$02,$02,$FC,$FC,$74,$FC,$FC,$F8,$FC,$07,$FB,$FD,$FD,$FD,$FD,$FD,$FB,$FE
  .byte $FF,$FF,$FF,$FF,$60,$9F,$0F,$0F,$0F,$08,$9F,$FF,$FF,$FF,$00,$FE,$FC,$F0,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$03,$06,$1C,$38,$70,$E0,$C0,$83,$3F,$FE,$C0,$00,$C0,$F8,$7F
  .byte $8F,$C1,$E0,$E0,$70,$F8,$DC,$CE,$CF,$07,$C3,$81,$80,$80,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$03,$0E,$78,$C0,$80,$00,$00,$00,$00,$00,$00,$40,$C0,$B8,$0F,$01,$01,$00,$00,$40
  .byte $C0,$F0,$18,$06,$01,$02,$00,$00,$00,$00,$C0,$C0,$C0,$20,$10,$08,$04,$02,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$80,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$80,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$03,$01,$00,$00,$00,$00,$00,$01,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$01,$03,$01,$00,$00,$00,$00,$00,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$E2,$3F,$03,$01,$00,$02,$1F,$F3,$80,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$03,$03,$07,$18,$30,$40,$80,$03,$03,$07,$08,$30,$60,$C0,$80,$80,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$01,$01,$00,$00,$00,$80,$C0,$F0,$78,$3E,$8F,$E7,$FF,$3F,$0F,$07,$02,$03,$07,$1F
  .byte $79,$F3,$C7,$0F,$1C,$3F,$7F,$EF,$CF,$80,$0F,$07,$07,$07,$00,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$80,$80,$80,$C0,$7F,$FF,$DD,$FF,$FF,$7E,$FF,$81,$7E,$FF,$FF,$FF,$FF,$FF,$7E,$FF
  .byte $FF,$FF,$FF,$FF,$18,$E7,$C3,$C3,$C3,$42,$E7,$FF,$FF,$FF,$00,$FF,$FF,$3C,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$C0,$40,$80,$80,$00,$00,$01,$07,$0E,$1C,$38,$F0,$E0,$4F,$7F,$70,$40,$70,$FE,$9F
  .byte $E3,$F0,$F8,$F8,$1C,$FE,$F7,$F3,$F3,$01,$F0,$E0,$E0,$E0,$00,$80,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$03,$1E,$30,$60,$C0,$80,$00,$00,$00,$00,$10,$F0,$EE,$83,$00,$00,$00,$00,$D0
  .byte $F0,$7C,$06,$01,$00,$00,$00,$80,$C0,$C0,$F0,$70,$30,$08,$04,$02,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$C0,$80,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$C0,$60,$40,$00,$00,$00
  .byte $00,$00,$00,$80,$40,$80,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$80,$40,$20,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$F8,$4F,$00,$00,$00,$00,$07,$7C,$20,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$01,$06,$0C,$10,$60,$C0,$40,$01,$02,$0C,$18,$30,$60,$20,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$80,$E0,$F0,$7C,$1E,$8F,$E3,$F9,$3F,$0F,$03,$01,$00,$00,$01,$07
  .byte $1E,$FC,$F1,$C3,$07,$0F,$1F,$3B,$F3,$E0,$C3,$01,$01,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$60,$60,$20,$30,$1F,$3F,$37,$3F,$3F,$9F,$FF,$E0,$DF,$FF,$FF,$FF,$BF,$FF,$DF,$FF
  .byte $7F,$FF,$FF,$FF,$06,$F9,$F0,$F0,$F0,$10,$F9,$FF,$FF,$FF,$00,$7F,$3F,$0F,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$30,$10,$20,$20,$C0,$C0,$40,$C1,$C3,$87,$CE,$7C,$B8,$D3,$DF,$DC,$D0,$DC,$BF,$E7
  .byte $F8,$FC,$FE,$FE,$07,$FF,$FD,$FC,$FC,$80,$FC,$F8,$F8,$F8,$00,$E0,$C0,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$07,$0C,$18,$30,$60,$C0,$80,$00,$00,$04,$3C,$FB,$E0,$00,$00,$00,$80,$F4
  .byte $FC,$1F,$01,$00,$00,$80,$C0,$E0,$F0,$70,$3C,$1C,$0C,$02,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$30,$E0,$80,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$80,$F0,$18,$10,$00,$00,$00
  .byte $00,$00,$80,$60,$10,$20,$00,$00,$00,$00,$00,$00,$00,$00,$00,$80,$40,$20,$10,$08,$00,$00,$00,$00,$00,$00,$00,$00
; owner piece of every byte (20 = empty)
CO_OWN:
  .byte $14,$14,$14,$14,$14,$14,$14,$14,$05,$05,$05,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$07,$07,$07,$07,$14,$14,$14
  .byte $14,$14,$09,$09,$09,$09,$14,$14,$14,$14,$14,$14,$14,$14,$0B,$0B,$0B,$0B,$0B,$0B,$14,$14,$14,$14,$14,$14,$14,$14
  .byte $14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$05,$04,$04,$04,$04,$04,$04,$14,$14,$06,$06,$06,$06,$14,$14,$14,$08,$08
  .byte $08,$08,$14,$14,$14,$0A,$0A,$0A,$0A,$0A,$0A,$0A,$0A,$0B,$0B,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14
  .byte $14,$14,$14,$14,$14,$14,$14,$14,$03,$03,$03,$03,$02,$02,$02,$02,$02,$02,$01,$01,$01,$01,$01,$01,$01,$01,$01,$00
  .byte $01,$00,$00,$00,$0A,$00,$00,$00,$00,$00,$00,$00,$00,$00,$14,$00,$00,$00,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14
  .byte $14,$14,$14,$14,$14,$14,$14,$14,$03,$03,$03,$03,$02,$02,$02,$02,$02,$02,$01,$0C,$01,$01,$01,$01,$01,$01,$01,$00
  .byte $01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$14,$00,$00,$00,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14
  .byte $14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$0C,$0C,$0C,$0C,$0C,$0C,$0E,$0E,$0E,$0E,$0E,$14,$14,$14,$10,$10
  .byte $10,$10,$10,$12,$12,$12,$12,$12,$12,$12,$12,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14
  .byte $14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$0D,$0D,$14,$14,$14,$14,$0F,$0F,$0F,$14,$14,$14,$14,$14,$14,$14
  .byte $14,$14,$14,$11,$11,$11,$11,$11,$11,$11,$13,$13,$13,$13,$13,$13,$13,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14
  .byte $14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14
  .byte $14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14
  .byte $14,$14,$14,$14,$14,$14,$14,$14,$05,$05,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$07,$07,$07,$14,$14,$14
  .byte $14,$14,$14,$09,$09,$09,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$0B,$0B,$0B,$0B,$14,$14,$14,$14,$14,$14,$14,$14
  .byte $14,$14,$14,$14,$14,$14,$14,$14,$14,$05,$05,$04,$04,$04,$04,$04,$14,$14,$14,$06,$06,$06,$06,$14,$14,$14,$14,$08
  .byte $08,$08,$09,$09,$14,$14,$14,$0A,$0A,$0A,$0A,$0A,$0A,$0B,$0B,$0B,$0B,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14
  .byte $14,$14,$14,$14,$14,$14,$14,$14,$03,$03,$03,$03,$03,$02,$02,$04,$04,$04,$04,$01,$01,$06,$06,$01,$01,$01,$01,$08
  .byte $01,$00,$00,$00,$0A,$00,$00,$00,$00,$00,$00,$00,$00,$00,$14,$00,$00,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14
  .byte $14,$14,$14,$14,$14,$14,$14,$14,$03,$03,$03,$03,$02,$02,$02,$02,$02,$02,$01,$01,$01,$01,$01,$01,$01,$01,$01,$00
  .byte $01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$14,$00,$00,$00,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14
  .byte $14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$0C,$0C,$0C,$0C,$0C,$0E,$0E,$0E,$0E,$01,$14,$10,$10,$10
  .byte $10,$10,$10,$12,$12,$12,$12,$12,$00,$12,$00,$00,$00,$00,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14
  .byte $14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$0D,$0D,$0C,$14,$14,$0E,$0E,$0F,$0F,$14,$14,$14,$14,$14,$14,$14
  .byte $14,$10,$10,$11,$11,$11,$11,$11,$12,$12,$13,$13,$13,$13,$13,$13,$13,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14
  .byte $14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$0D,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14
  .byte $14,$14,$14,$14,$14,$14,$14,$14,$11,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14
  .byte $14,$14,$14,$14,$14,$14,$14,$14,$05,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$07,$07,$14,$14,$14
  .byte $14,$14,$14,$14,$09,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$0B,$0B,$14,$14,$14,$14,$14,$14,$14,$14
  .byte $14,$14,$14,$14,$14,$14,$14,$14,$05,$05,$05,$04,$04,$04,$14,$14,$14,$14,$14,$06,$06,$07,$07,$14,$14,$14,$14,$08
  .byte $08,$08,$09,$09,$09,$09,$14,$14,$14,$14,$0A,$0A,$0A,$0B,$0B,$0B,$0B,$0B,$0B,$14,$14,$14,$14,$14,$14,$14,$14,$14
  .byte $14,$14,$14,$14,$14,$14,$14,$14,$03,$03,$14,$04,$04,$04,$04,$04,$04,$04,$04,$01,$01,$06,$06,$01,$01,$01,$08,$08
  .byte $08,$00,$00,$00,$0A,$00,$00,$00,$00,$0A,$00,$00,$00,$00,$14,$00,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14
  .byte $14,$14,$14,$14,$14,$14,$14,$14,$03,$03,$03,$03,$02,$02,$02,$02,$02,$02,$01,$01,$01,$01,$01,$01,$01,$01,$01,$00
  .byte $01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$14,$00,$00,$00,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14
  .byte $14,$14,$14,$14,$14,$14,$14,$14,$03,$03,$03,$03,$14,$14,$14,$0C,$0C,$0C,$0C,$0C,$0E,$0E,$0E,$01,$01,$10,$10,$10
  .byte $10,$00,$00,$00,$12,$00,$00,$00,$00,$14,$00,$00,$00,$00,$14,$00,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14
  .byte $14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$0C,$0D,$0C,$0C,$0C,$0E,$0E,$0E,$0E,$14,$14,$14,$14,$14,$14,$14
  .byte $10,$10,$10,$11,$11,$11,$11,$12,$12,$12,$13,$13,$13,$13,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14
  .byte $14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$0D,$0D,$14,$14,$14,$14,$14,$0F,$0F,$14,$14,$14,$14,$14,$14,$14
  .byte $14,$14,$14,$14,$14,$14,$11,$11,$11,$11,$14,$14,$14,$14,$13,$13,$13,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14
  .byte $14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14
  .byte $14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14
  .byte $14,$14,$14,$14,$14,$14,$14,$14,$05,$05,$05,$05,$14,$14,$14,$14,$14,$14,$14,$14,$07,$07,$07,$07,$07,$14,$14,$14
  .byte $14,$09,$09,$09,$09,$09,$14,$14,$14,$14,$14,$14,$0B,$0B,$0B,$0B,$0B,$0B,$0B,$0B,$14,$14,$14,$14,$14,$14,$14,$14
  .byte $14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$04,$04,$04,$04,$04,$04,$04,$04,$04,$06,$06,$06,$06,$01,$14,$14,$08,$08
  .byte $08,$08,$00,$00,$0A,$00,$00,$0A,$0A,$0A,$0A,$0A,$00,$00,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14
  .byte $14,$14,$14,$14,$14,$14,$14,$14,$03,$03,$03,$03,$02,$02,$02,$02,$02,$02,$01,$01,$01,$01,$01,$01,$01,$01,$01,$00
  .byte $01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$14,$00,$00,$00,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14
  .byte $14,$14,$14,$14,$14,$14,$14,$14,$03,$03,$03,$03,$02,$02,$02,$02,$02,$0C,$0C,$0C,$01,$01,$01,$01,$01,$01,$10,$10
  .byte $01,$00,$00,$00,$12,$00,$00,$00,$00,$00,$00,$00,$00,$00,$14,$00,$00,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14
  .byte $14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$0C,$0C,$0C,$0C,$0C,$0C,$0E,$0E,$0E,$0E,$14,$14,$14,$14,$14,$10
  .byte $10,$10,$10,$11,$11,$12,$12,$12,$12,$12,$13,$13,$13,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14
  .byte $14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$0D,$0D,$14,$14,$14,$14,$14,$0F,$0F,$14,$14,$14,$14,$14,$14,$14
  .byte $14,$14,$14,$14,$14,$11,$11,$11,$11,$11,$14,$14,$13,$13,$13,$13,$13,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14
  .byte $14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$05,$05,$14,$14,$14,$14,$07,$07,$07,$14,$14,$14,$14,$14,$14,$14
  .byte $14,$14,$14,$14,$09,$09,$09,$09,$09,$09,$14,$14,$0B,$0B,$0B,$0B,$0B,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14
  .byte $14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$04,$04,$04,$04,$04,$04,$06,$06,$06,$06,$14,$14,$14,$14,$14,$08
  .byte $08,$08,$08,$08,$09,$0A,$0A,$0A,$0A,$0A,$0A,$0B,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14
  .byte $14,$14,$14,$14,$14,$14,$14,$14,$03,$03,$03,$03,$02,$02,$02,$02,$02,$02,$01,$01,$01,$01,$01,$01,$01,$01,$01,$00
  .byte $01,$00,$00,$00,$0A,$00,$00,$00,$00,$00,$00,$00,$00,$00,$14,$00,$00,$00,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14
  .byte $14,$14,$14,$14,$14,$14,$14,$14,$03,$03,$03,$03,$02,$02,$02,$02,$02,$02,$01,$0C,$01,$01,$01,$01,$01,$01,$01,$00
  .byte $01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$14,$00,$00,$00,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14
  .byte $14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0E,$0E,$0E,$0E,$14,$14,$14,$10,$10
  .byte $10,$10,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14
  .byte $14,$14,$14,$14,$14,$14,$14,$14,$0D,$0D,$0D,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$0F,$0F,$0F,$0F,$14,$14,$14
  .byte $14,$11,$11,$11,$11,$11,$14,$14,$14,$14,$14,$14,$14,$13,$13,$13,$13,$13,$13,$13,$14,$14,$14,$14,$14,$14,$14,$14
  .byte $14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14
  .byte $14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14
  .byte $14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$05,$05,$14,$14,$14,$14,$14,$07,$07,$14,$14,$14,$14,$14,$14,$14
  .byte $14,$14,$14,$14,$14,$14,$09,$09,$09,$09,$14,$14,$14,$0B,$0B,$0B,$0B,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14
  .byte $14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$04,$05,$04,$04,$04,$06,$06,$06,$06,$14,$14,$14,$14,$14,$14,$14
  .byte $08,$08,$08,$08,$09,$09,$0A,$0A,$0A,$0A,$0A,$0B,$0B,$0B,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14
  .byte $14,$14,$14,$14,$14,$14,$14,$14,$03,$03,$03,$03,$03,$02,$02,$02,$04,$04,$04,$01,$06,$06,$01,$01,$01,$01,$01,$08
  .byte $08,$00,$00,$00,$0A,$00,$00,$00,$00,$00,$00,$00,$00,$00,$14,$00,$00,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14
  .byte $14,$14,$14,$14,$14,$14,$14,$14,$03,$03,$03,$03,$02,$02,$02,$02,$02,$02,$01,$01,$01,$01,$01,$01,$01,$01,$01,$00
  .byte $01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$14,$00,$00,$00,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14
  .byte $14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0E,$0E,$0E,$01,$14,$10,$10,$10
  .byte $10,$12,$12,$12,$12,$12,$12,$12,$12,$12,$00,$00,$00,$00,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14
  .byte $14,$14,$14,$14,$14,$14,$14,$14,$0D,$0D,$0D,$0C,$0C,$14,$14,$14,$14,$14,$14,$0E,$0E,$0F,$0F,$0F,$0F,$14,$14,$10
  .byte $10,$11,$11,$11,$11,$11,$14,$14,$14,$14,$12,$12,$12,$13,$13,$13,$13,$13,$13,$14,$14,$14,$14,$14,$14,$14,$14,$14
  .byte $14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$0F,$14,$14,$14,$14
  .byte $14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$13,$14,$14,$14,$14,$14,$14,$14,$14
  .byte $14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$05,$05,$14,$14,$14,$14,$14,$07,$14,$14,$14,$14,$14,$14,$14,$14
  .byte $14,$14,$14,$14,$14,$14,$14,$09,$09,$09,$14,$14,$14,$14,$14,$0B,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14
  .byte $14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$05,$05,$04,$04,$14,$06,$07,$07,$07,$14,$14,$14,$14,$14,$14,$14
  .byte $14,$08,$08,$08,$09,$09,$09,$09,$0A,$0A,$0A,$0B,$0B,$0B,$0B,$0B,$0B,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14
  .byte $14,$14,$14,$14,$14,$14,$14,$14,$03,$03,$14,$14,$14,$04,$04,$04,$04,$04,$04,$06,$06,$06,$06,$01,$01,$01,$01,$08
  .byte $08,$08,$00,$00,$0A,$00,$00,$00,$00,$0A,$00,$00,$00,$00,$14,$00,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14
  .byte $14,$14,$14,$14,$14,$14,$14,$14,$03,$03,$03,$03,$02,$02,$02,$02,$02,$02,$01,$01,$01,$01,$01,$01,$01,$01,$01,$00
  .byte $01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$14,$00,$00,$00,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14
  .byte $14,$14,$14,$14,$14,$14,$14,$14,$03,$03,$03,$03,$14,$14,$0C,$0C,$0C,$0C,$0C,$0C,$01,$0E,$0E,$01,$01,$10,$10,$10
  .byte $10,$00,$00,$00,$12,$00,$00,$00,$00,$12,$00,$00,$00,$00,$14,$00,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14
  .byte $14,$14,$14,$14,$14,$14,$14,$14,$14,$0D,$0D,$0C,$0C,$0C,$0C,$14,$14,$14,$14,$0E,$0E,$0E,$0F,$14,$14,$14,$14,$10
  .byte $10,$11,$11,$11,$14,$14,$14,$12,$12,$12,$12,$12,$12,$13,$13,$13,$13,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14
  .byte $14,$14,$14,$14,$14,$14,$14,$14,$0D,$0D,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$0F,$0F,$0F,$14,$14,$14
  .byte $14,$14,$14,$11,$11,$11,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$13,$13,$13,$14,$14,$14,$14,$14,$14,$14,$14
  .byte $14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14
  .byte $14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14
  .byte $14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$05,$05,$14,$14,$14,$14,$07,$07,$07,$14,$14,$14,$14,$14,$14,$14
  .byte $14,$14,$14,$09,$09,$09,$09,$09,$09,$09,$0B,$0B,$0B,$0B,$0B,$0B,$0B,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14
  .byte $14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$04,$04,$04,$04,$04,$04,$06,$06,$06,$06,$06,$01,$14,$14,$08,$08
  .byte $08,$08,$08,$08,$0A,$00,$0A,$0A,$0A,$0A,$00,$00,$00,$00,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14
  .byte $14,$14,$14,$14,$14,$14,$14,$14,$03,$03,$03,$03,$02,$02,$02,$02,$02,$02,$01,$01,$01,$01,$01,$01,$01,$01,$01,$00
  .byte $01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$14,$00,$00,$00,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14
  .byte $14,$14,$14,$14,$14,$14,$14,$14,$03,$03,$03,$03,$02,$02,$02,$02,$02,$0C,$0C,$0C,$01,$01,$0E,$01,$01,$01,$10,$10
  .byte $01,$00,$00,$00,$12,$00,$00,$00,$00,$00,$00,$00,$00,$00,$14,$00,$00,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14
  .byte $14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$0D,$0C,$0C,$0C,$0C,$0C,$0C,$14,$14,$0E,$0E,$0E,$0E,$14,$14,$14,$10,$10
  .byte $10,$11,$11,$14,$14,$12,$12,$12,$12,$12,$12,$12,$12,$13,$13,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14
  .byte $14,$14,$14,$14,$14,$14,$14,$14,$0D,$0D,$0D,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$0F,$0F,$0F,$0F,$14,$14,$14
  .byte $14,$14,$11,$11,$11,$11,$14,$14,$14,$14,$14,$14,$14,$14,$14,$13,$13,$13,$13,$13,$14,$14,$14,$14,$14,$14,$14,$14

; big letters of the title from 96 (third 0)
BIG_P:
  .byte $00,$1F,$1F,$18,$18,$18,$18,$18,$00,$E0,$E0,$18,$18,$18,$18,$18
  .byte $18,$18,$18,$18,$18,$1F,$1F,$00,$18,$18,$18,$18,$18,$E0,$E0,$00
  .byte $00,$1F,$1F,$18,$18,$18,$18,$1F,$00,$F8,$F8,$00,$00,$00,$00,$E0
  .byte $1F,$18,$18,$18,$18,$1F,$1F,$00,$E0,$00,$00,$00,$00,$F8,$F8,$00
  .byte $00,$1F,$1F,$18,$18,$18,$18,$1F,$00,$E0,$E0,$18,$18,$18,$18,$E0
  .byte $1F,$18,$18,$18,$18,$18,$18,$00,$E0,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$07,$07,$18,$18,$18,$18,$07,$00,$E0,$E0,$18,$18,$00,$00,$E0
  .byte $07,$00,$00,$18,$18,$07,$07,$00,$E0,$18,$18,$18,$18,$E0,$E0,$00
  .byte $00,$01,$01,$06,$06,$18,$18,$18,$00,$80,$80,$60,$60,$18,$18,$18
  .byte $18,$1F,$1F,$18,$18,$18,$18,$00,$18,$F8,$F8,$18,$18,$18,$18,$00
  .byte $00,$07,$07,$18,$18,$18,$18,$18,$00,$E0,$E0,$18,$18,$00,$00,$00
  .byte $18,$18,$18,$18,$18,$07,$07,$00,$00,$00,$00,$18,$18,$E0,$E0,$00
  .byte $00,$18,$18,$1E,$1E,$19,$19,$19,$00,$18,$18,$78,$78,$98,$98,$98
  .byte $19,$18,$18,$18,$18,$18,$18,$00,$98,$18,$18,$18,$18,$18,$18,$00
  .byte $00,$07,$07,$01,$01,$01,$01,$01,$00,$E0,$E0,$80,$80,$80,$80,$80
  .byte $01,$01,$01,$01,$01,$07,$07,$00,$80,$80,$80,$80,$80,$E0,$E0,$00
  .byte $00,$18,$18,$18,$18,$1E,$1E,$19,$00,$18,$18,$18,$18,$18,$18,$98
  .byte $19,$18,$18,$18,$18,$18,$18,$00,$98,$78,$78,$18,$18,$18,$18,$00
  .byte $00,$1F,$1F,$18,$18,$18,$18,$1F,$00,$E0,$E0,$18,$18,$18,$18,$E0
  .byte $1F,$19,$19,$18,$18,$18,$18,$00,$E0,$80,$80,$60,$60,$18,$18,$00
BIG_C:
  .byte $B0,$B0,$B0,$B0,$A0,$A0,$A0,$A0,$B0,$B0,$B0,$B0,$A0,$A0,$A0,$A0
  .byte $90,$90,$90,$90,$80,$80,$80,$80,$90,$90,$90,$90,$80,$80,$80,$80
  .byte $B0,$B0,$B0,$B0,$A0,$A0,$A0,$A0,$B0,$B0,$B0,$B0,$A0,$A0,$A0,$A0
  .byte $90,$90,$90,$90,$80,$80,$80,$80,$90,$90,$90,$90,$80,$80,$80,$80
  .byte $B0,$B0,$B0,$B0,$A0,$A0,$A0,$A0,$B0,$B0,$B0,$B0,$A0,$A0,$A0,$A0
  .byte $90,$90,$90,$90,$80,$80,$80,$80,$90,$90,$90,$90,$80,$80,$80,$80
  .byte $B0,$B0,$B0,$B0,$A0,$A0,$A0,$A0,$B0,$B0,$B0,$B0,$A0,$A0,$A0,$A0
  .byte $90,$90,$90,$90,$80,$80,$80,$80,$90,$90,$90,$90,$80,$80,$80,$80
  .byte $B0,$B0,$B0,$B0,$A0,$A0,$A0,$A0,$B0,$B0,$B0,$B0,$A0,$A0,$A0,$A0
  .byte $90,$90,$90,$90,$80,$80,$80,$80,$90,$90,$90,$90,$80,$80,$80,$80
  .byte $B0,$B0,$B0,$B0,$A0,$A0,$A0,$A0,$B0,$B0,$B0,$B0,$A0,$A0,$A0,$A0
  .byte $90,$90,$90,$90,$80,$80,$80,$80,$90,$90,$90,$90,$80,$80,$80,$80
  .byte $B0,$B0,$B0,$B0,$A0,$A0,$A0,$A0,$B0,$B0,$B0,$B0,$A0,$A0,$A0,$A0
  .byte $90,$90,$90,$90,$80,$80,$80,$80,$90,$90,$90,$90,$80,$80,$80,$80
  .byte $B0,$B0,$B0,$B0,$A0,$A0,$A0,$A0,$B0,$B0,$B0,$B0,$A0,$A0,$A0,$A0
  .byte $90,$90,$90,$90,$80,$80,$80,$80,$90,$90,$90,$90,$80,$80,$80,$80
  .byte $B0,$B0,$B0,$B0,$A0,$A0,$A0,$A0,$B0,$B0,$B0,$B0,$A0,$A0,$A0,$A0
  .byte $90,$90,$90,$90,$80,$80,$80,$80,$90,$90,$90,$90,$80,$80,$80,$80
  .byte $B0,$B0,$B0,$B0,$A0,$A0,$A0,$A0,$B0,$B0,$B0,$B0,$A0,$A0,$A0,$A0
  .byte $90,$90,$90,$90,$80,$80,$80,$80,$90,$90,$90,$90,$80,$80,$80,$80
BIG_LEN = 320
TXT_BIG:
  .byte 3,6,96,97,100,101,100,101,104,105,32,32,108,109,104,105,112,113,116,117,100,101,0
  .byte 4,6,98,99,102,103,102,103,106,107,32,32,110,111,106,107,114,115,118,119,102,103,0
  .byte 6,11,120,121,124,125,128,129,100,101,132,133,0
  .byte 7,11,122,123,126,127,130,131,102,103,134,135,0
  .byte $FF

; one-shot tone effects: period and volume for every frame
WH_TL:
  .byte $00,$1A,$1F,$26,$31,$45,$24,$24,$24,$18,$18,$18,$18,$18,$D0,$A1
  .byte $83,$6F,$60,$54,$4B,$44,$3E,$39,$35,$31,$2E,$2B,$29,$26,$25,$23
  .byte $54,$78,$54,$78,$54,$78,$54,$78,$54,$78,$54,$78,$54,$78,$54,$78
  .byte $3F,$3F,$3F,$3F,$00,$00,$EF,$EF,$EF,$EF,$EF,$EF,$95,$97,$90,$92
  .byte $9E,$A0,$99,$9B,$A8,$AB,$A2,$A5,$B4,$B7,$AD,$B0,$C1,$C5,$B9,$BD
  .byte $D0,$D5,$C8,$CC,$E2,$E7,$D8,$DD,$F8,$FE,$EC,$F1,$12,$1A,$03,$0A
  .byte $32,$3C,$20,$28,$34,$37,$34,$36,$3F,$42,$3E,$41,$4B,$4F,$4B,$4F
  .byte $5B,$5F,$5A,$5E,$6D,$72,$6C,$72,$83,$89,$82,$89,$9D,$A5,$9D,$A4
  .byte $BD,$C6,$BC,$C5,$E3,$EE,$E3,$ED,$11,$1E,$10,$1D,$50,$50,$50,$50
  .byte $50,$00,$00,$3C,$3C,$3C,$3C,$3C,$00,$00,$2F,$2F,$2F,$2F,$2F,$00
  .byte $00,$28,$28,$28,$28,$28,$28,$28,$28,$9F,$9F,$9F,$9F,$9F,$9F,$9F
  .byte $9F,$A9,$A9,$A9,$A9,$A9,$A9,$A9,$A9,$B3,$B3,$B3,$B3,$B3,$B3,$B3
  .byte $B3,$D5,$D5,$D5,$D5,$D5,$D5,$D5,$D5,$D5,$D5,$D5,$D5,$D5,$D5,$D5
  .byte $D5,$D5,$D5,$D5,$D5,$D5,$D5,$28,$28,$28,$A1,$A1,$A1,$A1,$18,$20
  .byte $20,$6A,$6A,$6A,$6A,$47,$47,$47,$47,$54,$54,$54,$35,$35,$35,$35
  .byte $35,$35,$35,$35,$35,$35,$35,$35
WH_TH:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $01,$01,$01,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$01,$01,$01
  .byte $01,$01,$01,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$01,$01,$01,$01,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$01,$01,$01,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
WH_VOL:
  .byte $00,$09,$08,$07,$05,$04,$0C,$0B,$09,$0C,$0B,$09,$08,$06,$0D,$0D
  .byte $0C,$0C,$0C,$0B,$0B,$0B,$0A,$0A,$09,$09,$09,$08,$08,$08,$07,$07
  .byte $0E,$0D,$0C,$0B,$0A,$09,$08,$07,$06,$05,$04,$03,$03,$03,$03,$03
  .byte $0B,$0A,$09,$08,$00,$00,$0B,$0A,$09,$07,$06,$05,$0D,$0D,$0D,$0D
  .byte $0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D
  .byte $0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0C,$0B,$0A,$09,$08
  .byte $07,$06,$05,$04,$0D,$0D,$0D,$0D,$0C,$0C,$0C,$0C,$0B,$0B,$0B,$0B
  .byte $0A,$0A,$0A,$0A,$09,$09,$09,$09,$08,$08,$08,$08,$07,$07,$07,$07
  .byte $06,$06,$06,$06,$05,$05,$05,$05,$04,$04,$04,$04,$0D,$0C,$0B,$0A
  .byte $09,$00,$00,$0D,$0C,$0B,$0A,$09,$00,$00,$0D,$0C,$0B,$0A,$09,$00
  .byte $00,$0D,$0C,$0A,$09,$08,$07,$05,$04,$0C,$0B,$0A,$09,$09,$08,$07
  .byte $06,$0C,$0B,$0A,$09,$09,$08,$07,$06,$0C,$0B,$0A,$09,$09,$08,$07
  .byte $06,$0C,$0C,$0B,$0B,$0B,$0B,$0A,$0A,$0A,$09,$09,$09,$09,$08,$08
  .byte $08,$07,$07,$07,$07,$06,$06,$0C,$0A,$08,$09,$08,$07,$06,$0A,$08
  .byte $05,$0C,$0B,$0A,$09,$0C,$0B,$0A,$09,$0C,$0B,$09,$0D,$0C,$0B,$0A
  .byte $09,$08,$08,$07,$06,$05,$04,$03
WH_START:
  .byte $00,$01,$06,$0E,$20,$30,$3C,$64,$8C,$A9,$D7,$DA,$DE,$E1
WH_LEN:
  .byte $00,$05,$08,$12,$10,$0C,$28,$28,$1D,$2E,$03,$04,$03,$17
W_SHOT = 1
W_CRYS = 2
W_CHARGE = 3
W_CLANG = 4
W_PIECE = 5
W_CREAK = 6
W_DIE = 7
W_EXTRA = 8
W_OVER = 9
W_BONUS = 10
W_EMPTY = 11
W_KEY = 12
W_SIGN = 13

; noise effects: noise volume / period, low tone volume / period for every frame
EX_NV:
  .byte $00,$0F,$0F,$0F,$0F,$0E,$0E,$0E,$0E,$0D,$0D,$0D,$0D,$0C,$0C,$0C
  .byte $0C,$0B,$0B,$0B,$0B,$0A,$0A,$0A,$0A,$09,$09,$09,$09,$08,$08,$08
  .byte $08,$07,$07,$07,$07,$06,$06,$06,$06,$05,$05,$05,$05,$04,$04,$04
  .byte $04,$03,$03,$03,$03,$02,$02,$02,$02,$01,$01,$01,$01,$0A,$09,$08
  .byte $07,$06,$05,$0E,$0E,$0D,$0D,$0C,$0C,$0B,$0B,$0A,$0A,$09,$09,$08
  .byte $08,$07,$07,$06,$06,$05,$05,$09,$07,$05,$03,$01,$00,$00
EX_NP:
  .byte $00,$14,$14,$14,$14,$14,$14,$14,$14,$15,$15,$15,$15,$15,$15,$15
  .byte $15,$16,$16,$16,$16,$16,$16,$16,$16,$17,$17,$17,$17,$17,$17,$17
  .byte $17,$18,$18,$18,$18,$18,$18,$18,$18,$19,$19,$19,$19,$19,$19,$19
  .byte $19,$1A,$1A,$1A,$1A,$1A,$1A,$1A,$1A,$1B,$1B,$1B,$1B,$02,$04,$02
  .byte $04,$02,$04,$10,$10,$10,$10,$11,$11,$11,$11,$12,$12,$12,$12,$13
  .byte $13,$13,$13,$14,$14,$14,$14,$1C,$1C,$1C,$1C,$1C,$1C,$1C
EX_VC:
  .byte $00,$0D,$0D,$0D,$0D,$0C,$0C,$0C,$0C,$0B,$0B,$0B,$0B,$0A,$0A,$0A
  .byte $0A,$09,$09,$09,$09,$08,$08,$08,$08,$07,$07,$07,$07,$06,$06,$06
  .byte $06,$05,$05,$05,$05,$04,$04,$04,$04,$03,$03,$03,$03,$02,$02,$02
  .byte $02,$01,$01,$01,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$0C,$0C,$0B,$0B,$0A,$0A,$09,$09,$08,$08,$07,$07,$06
  .byte $06,$05,$05,$04,$04,$03,$03,$0D,$0B,$09,$07,$05,$03,$01
EX_TL:
  .byte $00,$70,$7D,$70,$7D,$70,$7D,$70,$7D,$70,$7D,$70,$7D,$70,$7D,$70
  .byte $7D,$70,$7D,$70,$7D,$70,$7D,$70,$7D,$70,$7D,$70,$7D,$70,$7D,$70
  .byte $7D,$70,$7D,$70,$7D,$70,$7D,$70,$7D,$70,$7D,$70,$7D,$70,$7D,$70
  .byte $7D,$70,$7D,$70,$7D,$70,$7D,$70,$7D,$70,$7D,$70,$7D,$00,$00,$00
  .byte $00,$00,$00,$7D,$B6,$7D,$B6,$7D,$B6,$7D,$B6,$7D,$B6,$7D,$B6,$7D
  .byte $B6,$7D,$B6,$7D,$B6,$7D,$B6,$16,$16,$16,$16,$16,$16,$16
EX_TH:
  .byte $00,$04,$03,$04,$03,$04,$03,$04,$03,$04,$03,$04,$03,$04,$03,$04
  .byte $03,$04,$03,$04,$03,$04,$03,$04,$03,$04,$03,$04,$03,$04,$03,$04
  .byte $03,$04,$03,$04,$03,$04,$03,$04,$03,$04,$03,$04,$03,$04,$03,$04
  .byte $03,$04,$03,$04,$03,$04,$03,$04,$03,$04,$03,$04,$03,$00,$00,$00
  .byte $00,$00,$00,$03,$02,$03,$02,$03,$02,$03,$02,$03,$02,$03,$02,$03
  .byte $02,$03,$02,$03,$02,$03,$02,$05,$05,$05,$05,$05,$05,$05
EX_START:
  .byte $00,$01,$3D,$43,$57
EX_LEN:
  .byte $00,$3C,$06,$14,$07
S_BIG = 1
S_DRILL = 2
S_BOOM = 3
S_STEP = 4

; speed tables: speeds 0.5, 0.75, 1, 1.25, 1.5, 2, 3, 4, 0.07 pixels a frame (index speed x 16 + direction)
VEL_XL:
  .byte $00,$31,$5B,$76,$80,$76,$5B,$31,$00,$CF,$A5,$8A,$80,$8A,$A5,$CF
  .byte $00,$49,$88,$B1,$C0,$B1,$88,$49,$00,$B7,$78,$4F,$40,$4F,$78,$B7
  .byte $00,$62,$B5,$ED,$00,$ED,$B5,$62,$00,$9E,$4B,$13,$00,$13,$4B,$9E
  .byte $00,$7A,$E2,$28,$40,$28,$E2,$7A,$00,$86,$1E,$D8,$C0,$D8,$1E,$86
  .byte $00,$93,$10,$63,$80,$63,$10,$93,$00,$6D,$F0,$9D,$80,$9D,$F0,$6D
  .byte $00,$C4,$6A,$D9,$00,$D9,$6A,$C4,$00,$3C,$96,$27,$00,$27,$96,$3C
  .byte $00,$26,$1F,$C6,$00,$C6,$1F,$26,$00,$DA,$E1,$3A,$00,$3A,$E1,$DA
  .byte $00,$88,$D4,$B2,$00,$B2,$D4,$88,$00,$78,$2C,$4E,$00,$4E,$2C,$78
  .byte $00,$07,$0D,$11,$12,$11,$0D,$07,$00,$F9,$F3,$EF,$EE,$EF,$F3,$F9
VEL_XH:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$FF,$FF,$FF,$FF,$FF,$FF,$FF
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$FF,$FF,$FF,$FF,$FF,$FF,$FF
  .byte $00,$00,$00,$00,$01,$00,$00,$00,$00,$FF,$FF,$FF,$FF,$FF,$FF,$FF
  .byte $00,$00,$00,$01,$01,$01,$00,$00,$00,$FF,$FF,$FE,$FE,$FE,$FF,$FF
  .byte $00,$00,$01,$01,$01,$01,$01,$00,$00,$FF,$FE,$FE,$FE,$FE,$FE,$FF
  .byte $00,$00,$01,$01,$02,$01,$01,$00,$00,$FF,$FE,$FE,$FE,$FE,$FE,$FF
  .byte $00,$01,$02,$02,$03,$02,$02,$01,$00,$FE,$FD,$FD,$FD,$FD,$FD,$FE
  .byte $00,$01,$02,$03,$04,$03,$02,$01,$00,$FE,$FD,$FC,$FC,$FC,$FD,$FE
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$FF,$FF,$FF,$FF,$FF,$FF,$FF
VEL_YL:
  .byte $80,$8A,$A5,$CF,$00,$31,$5B,$76,$80,$76,$5B,$31,$00,$CF,$A5,$8A
  .byte $40,$4F,$78,$B7,$00,$49,$88,$B1,$C0,$B1,$88,$49,$00,$B7,$78,$4F
  .byte $00,$13,$4B,$9E,$00,$62,$B5,$ED,$00,$ED,$B5,$62,$00,$9E,$4B,$13
  .byte $C0,$D8,$1E,$86,$00,$7A,$E2,$28,$40,$28,$E2,$7A,$00,$86,$1E,$D8
  .byte $80,$9D,$F0,$6D,$00,$93,$10,$63,$80,$63,$10,$93,$00,$6D,$F0,$9D
  .byte $00,$27,$96,$3C,$00,$C4,$6A,$D9,$00,$D9,$6A,$C4,$00,$3C,$96,$27
  .byte $00,$3A,$E1,$DA,$00,$26,$1F,$C6,$00,$C6,$1F,$26,$00,$DA,$E1,$3A
  .byte $00,$4E,$2C,$78,$00,$88,$D4,$B2,$00,$B2,$D4,$88,$00,$78,$2C,$4E
  .byte $EE,$EF,$F3,$F9,$00,$07,$0D,$11,$12,$11,$0D,$07,$00,$F9,$F3,$EF
VEL_YH:
  .byte $FF,$FF,$FF,$FF,$00,$00,$00,$00,$00,$00,$00,$00,$00,$FF,$FF,$FF
  .byte $FF,$FF,$FF,$FF,$00,$00,$00,$00,$00,$00,$00,$00,$00,$FF,$FF,$FF
  .byte $FF,$FF,$FF,$FF,$00,$00,$00,$00,$01,$00,$00,$00,$00,$FF,$FF,$FF
  .byte $FE,$FE,$FF,$FF,$00,$00,$00,$01,$01,$01,$00,$00,$00,$FF,$FF,$FE
  .byte $FE,$FE,$FE,$FF,$00,$00,$01,$01,$01,$01,$01,$00,$00,$FF,$FE,$FE
  .byte $FE,$FE,$FE,$FF,$00,$00,$01,$01,$02,$01,$01,$00,$00,$FF,$FE,$FE
  .byte $FD,$FD,$FD,$FE,$00,$01,$02,$02,$03,$02,$02,$01,$00,$FE,$FD,$FD
  .byte $FC,$FC,$FD,$FE,$00,$01,$02,$03,$04,$03,$02,$01,$00,$FE,$FD,$FC
  .byte $FF,$FF,$FF,$FF,$00,$00,$00,$00,$00,$00,$00,$00,$00,$FF,$FF,$FF
; fighters: where they keep round the ship
ORBIT_X:
  .byte $00,$18,$2D,$3B,$40,$3B,$2D,$18,$00,$E8,$D3,$C5,$C0,$C5,$D3,$E8
ORBIT_Y:
  .byte $C8,$CC,$D8,$EB,$00,$15,$28,$34,$38,$34,$28,$15,$00,$EB,$D8,$CC

GFX_LOAD:
  .byte 1, $00,$41, <512,>512, <FONT,>FONT
  .byte 2, $00,$61, <512,>512, $F0,0
  .byte 1, $08,$40, <128,>128, <FAR_PAT,>FAR_PAT
  .byte 2, $08,$60, <128,>128, $40,0
  .byte 1, $88,$40, <16,>16, <ICON_PAT,>ICON_PAT
  .byte 1, $88,$60, <16,>16, <ICON_COL,>ICON_COL
  .byte 2, $60,$65, <672,>672, $E0,0
  .byte 1, $00,$49, <512,>512, <FONT,>FONT
  .byte 2, $00,$69, <512,>512, $F0,0
  .byte 1, $08,$48, <128,>128, <FAR_PAT,>FAR_PAT
  .byte 2, $08,$68, <128,>128, $40,0
  .byte 1, $88,$48, <16,>16, <ICON_PAT,>ICON_PAT
  .byte 1, $88,$68, <16,>16, <ICON_COL,>ICON_COL
  .byte 2, $60,$6D, <672,>672, $E0,0
  .byte 1, $00,$51, <512,>512, <FONT,>FONT
  .byte 2, $00,$71, <512,>512, $F0,0
  .byte 1, $08,$50, <128,>128, <FAR_PAT,>FAR_PAT
  .byte 2, $08,$70, <128,>128, $40,0
  .byte 1, $88,$50, <16,>16, <ICON_PAT,>ICON_PAT
  .byte 1, $88,$70, <16,>16, <ICON_COL,>ICON_COL
  .byte 2, $60,$75, <672,>672, $E0,0
  .byte 2, $00,$45, <96,>96, 0,0
  .byte 2, $00,$65, <96,>96, $F4,0
  .byte 0
STAR_LOAD:
  .byte 1, $00,$43, <512,>512, <NEAR_PAT,>NEAR_PAT
  .byte 2, $00,$63, <512,>512, $E0,0
  .byte 1, $00,$4B, <512,>512, <NEAR_PAT,>NEAR_PAT
  .byte 2, $00,$6B, <512,>512, $E0,0
  .byte 1, $00,$53, <512,>512, <NEAR_PAT,>NEAR_PAT
  .byte 2, $00,$73, <512,>512, $E0,0
  .byte 0
