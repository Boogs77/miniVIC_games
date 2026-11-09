;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;                                                              ;
;   LITTLE 6502 GUY  -  an original life simulation            ;
;   65C02 assembly, TMS9918A Graphics II (tiles + sprites)     ;
;                                                              ;
;   - Six lives in a little house of three floors built on     ;
;     the 6502 chip of the miniVIC, with Byte, his black cat   ;
;   - he has needs (food, drink, sleep, cleanliness, fun,      ;
;     health) and a day of his own: he sleeps, eats, takes a   ;
;     bath, reads, plays records, rides his bike, tinkers,     ;
;     uses his tiny PC and writes letters                      ;
;   - one game hour = one minute (four times faster while he   ;
;     sleeps); the house is saved on the SD every hour and at  ;
;     SAVE AND QUIT (zone 39, lib_records.asm)                 ;
;   - the joystick menu: bring food and water, feed Byte,      ;
;     send a gift, ask Six to do something (better with        ;
;     PLEASE), knock on the glass, read his letters            ;
;   - HI-LO BITS: 8-bit numbers on 8 lights, higher or lower,  ;
;     ten rounds against Six                                   ;
;   - SOUND (2 x AY-3-8910, played from the NMI at 60 Hz):     ;
;     the title tune, four records, the sounds of the house    ;
;   - the main loop writes the VDP only with the interrupt     ;
;     off (VDP_INT_OFF just after the NMI); the NMI only       ;
;     copies the SAT and plays the sound                       ;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; ---------------- Six at HI-LO BITS ----------------
AI_HILO_ERR = 56         ; out of 256: Six guesses against the odds
AI_HILO_LUCK = 40        ; out of 256: near the middle Six guesses at random

; ---------------- zero page: game ----------------
CLKF        = $30      ; frames to the next game minute
SIXX        = $31      ; Six: left x of the sprite, top y, floor (0 attic, 1 first, 2 ground)
SIXY        = $32
SIXF        = $33
TGTX        = $34      ; where he is going
TGTF        = $35
ACT         = $36      ; activity (A_*)
APH         = $37      ; 0 going there, 1 doing it, 2 nothing to do
ATIME       = $38      ; minutes left of the activity
LASTA       = $39      ; the activity before
FACE        = $3A      ; 0 right, 1 left
WALKC       = $3B      ; frames walked (the steps)
NEXTA       = $3C      ; activity asked for ($FF = none)
SPKT        = $3D      ; frames the words stay on row 22
DIRTY       = $3E      ; to draw again (D_*)
MENU        = $3F      ; 0 closed, 1 main, 2 gifts, 3 ask, 4 letters
MSEL        = $40      ; the item chosen
PLEASE      = $41      ; 1 = "please" in the request
JPREV       = $42      ; joysticks the frame before
JNEW        = $43      ; new presses
SNDT        = $44      ; frames to the next sound of the activity
SLEEPING    = $45      ; 1 = asleep (time runs four times faster)
MOOD        = $46      ; 0-255
FACEI       = $47      ; mood class (0 happy, 1 fine, 2 sad, 3 sick)
WAVET       = $48      ; frames of a reaction (he turns and waves)
RPROP       = $49      ; prop of the reaction (0 = none)
LOWN        = $4A      ; needs already said to be low (bits)
SAVEREQ     = $4B      ; 1 = save at the end of the frame
GOGAME      = $4C      ; 1 = HI-LO BITS begins
OBJA        = $4D      ; object of the activity ($FF = none)
CATX        = $4E      ; Byte: x, y, floor, target x, target floor
CATY        = $4F
CATF        = $50
CTGX        = $51
CTGF        = $52
CATA        = $53      ; 0 walking, 1 sitting, 2 sleeping, 3 eating
CATT        = $54      ; frames / 4 of what he does
CATP        = $55      ; his pattern
CATW        = $56      ; frames walked
CATNEXT     = $57      ; what he does when he arrives
MEOWT       = $58      ; frames to the next meow
CONFIRM     = $59      ; title: button 2 pressed once (new house)
HASSAVE     = $5A      ; 1 = a house was found on the SD
ST_OLD      = $5B      ; copy of the house to write next (0 / 1)
ST_CNT      = $5C      ; 2 bytes: counter of the writes
RECX        = $5E      ; temporaries of the menu
RECY        = $5F
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
HLN         = $72      ; HI-LO BITS: the number shown, the next one
HLM         = $73
HLYOU       = $74      ;   points of the player and of Six
HLSIX       = $75
HLR         = $76      ;   round 1-10
HLG         = $77      ;   the guesses: 1 higher, 0 lower
HLS         = $78
NUM16       = $79      ; 2 bytes: a number to print
LSLOT       = $7B      ; the letter shown
LSEED       = $7C
SPKP        = $7D      ; 2 bytes: the words of Six on row 22
P_JOY       = $80      ; 2 bytes (joystick, 1 = pressed)
NLET        = $82      ; letters that can be read (0-4)
MITEMS      = $83      ; items of the menu open
SPRN        = $84      ; sprites in the SAT
SATB        = $85      ; bytes of the SAT to copy
HOFF        = $86      ; name table of NT_XY and CLEAR_NT (always 0 here)
JOYC        = $87      ; the two joysticks together
ANIMT       = $88      ; frames to the next frame of the object
OBJST       = $89      ; state of the object shown
PROPN       = $8A      ; prop sprite (pattern, 0 = none), x, y, colour
PROPX       = $8B
PROPY       = $8C
PROPC       = $8D
TICKS       = $8F      ; game minutes done (tests)

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

OX         = $E0         ; sprite being added: left x, top y, pattern, colour
OY         = $E1
ON         = $E2
OC         = $E3

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
SONG       = $0730       ; tune to play
CMD_GAME   = 1           ; silence + game effects
CMD_START  = 2           ; the tune SONG
S_BIG      = $FE         ; (lib_sound: no noise is "big" here)

; ---------------- the house: saved on the SD ----------------
STATE      = $0400
S_DAY      = $0400       ; 2 bytes: day of the house (1-9999)
S_HOUR     = $0402
S_MIN      = $0403
NEED       = $0404       ; 6 bytes: 0-255, 255 = all right
N_FOOD     = 0
N_DRINK    = 1
N_REST     = 2
N_CLEAN    = 3
N_FUN      = 4
N_HEALTH   = 5
S_FRIDGE   = $040A       ; meals in the fridge (0-9)
S_WATER    = $040B       ; bottles of water (0-9)
S_PERS     = $040C       ; character (0 tidy, 1 lazy, 2 musical, 3 sporty, 4 bookish, 5 foodie)
S_BOOKS    = $040D
S_RECS     = $040E       ; records given (0-3)
S_BALL     = $040F       ; 1 = he has a ball
S_FLOWER   = $0410       ; days the flowers last (0 none, 1 wilted)
S_HAPPY    = $0411       ; joy from gifts, knocks, games (fades)
S_ANNOY    = $0412       ; too many requests (fades)
S_BEST     = $0413       ; best HI-LO BITS of the player (points)
S_LASTG    = $0414       ; last gift + 1 since the last letter
S_HILO     = $0415       ; last HI-LO BITS since the letter: 0 none, 1 Six won, 2 you won
S_LETD     = $0416       ; day (low) of the last letter
S_LETN     = $0417       ; letters written (stops at 255)
S_UNREAD   = $0418       ; 1 = a letter in the mailbox
S_CATF     = $0419       ; Byte: 255 = full
S_BOWL     = $041A       ; portions in his bowl (0-6)
S_FLR      = $041B       ; where Six is
S_X        = $041C
S_GIVEN    = $041D       ; 6 bytes: gifts of every kind
S_DCNT     = $0423       ; 5 bytes: minutes to the next drop of every need
S_LETS     = $0430       ; 4 letters x 8 bytes: day lo, day hi, mood, gift+1, want, hi-lo, seed, cat
ST_LEN     = $50

; ---------------- other RAM ----------------
SAT_BUFFER = $0600       ; 32 sprites x 4 + end of list
LTXT       = $0200       ; a line of a letter being composed (32 bytes)

; ---------------- parameters ----------------
BTN_MASK    = %00110000
J_UP        = %00000001
J_DOWN      = %00000010
J_LEFT      = %00000100
J_RIGHT     = %00001000
J_B1        = %00010000
J_B2        = %00100000
D_CLOCK     = 1          ; row 0: day and time
D_HUD       = 2          ; row 0: mood, fridge, water, bowl, mail
D_BARS      = 4          ; rows 20-21
D_ROW22     = 8          ; row 22: words or menu title
D_ROW23     = 16         ; row 23: hint or menu item
LADX        = 28         ; x of Six on the ladder
C_SUIT      = 4          ; colours: overalls and hair, skin, Byte
C_SKIN      = 9
C_CAT       = 1

; ---------------- records on the SD (lib_records.asm: only SV_CALL is used) ----------------
REC_ZONE    = 39         ; fixed zone of the game in the save area
REC_RAM     = $7D00      ; $2A0 bytes after the program
REC_ROW     = 9
REC_WIPEN   = 10
REC_JOY2    = $FF
REC_SROW    = REC_ROW
ST_SEC      = 2          ; the house: sectors 2 and 3 of the zone, written in turn

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
  STZ TICKS
  LDA #$A5
  STA RND
  JSR REC_INIT                 ; the BIOS check (SV_OK)
  JSR ST_LOAD                  ; the house from the SD, if there is one
  JSR HIDE_SPRITES
  JMP TITLE


; ===============================================================
;  TITLE: the name, Six waving, CONTINUE / NEW HOUSE
; ===============================================================
TITLE:
  LDX #$FF
  TXS
  JSR HIDE_SPRITES
  STZ CONFIRM
  JSR VDP_INT_OFF
  JSR CLEAR_NT
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
  JSR TITLE_STATUS
  STZ SONG                     ; the title tune
  LDA #CMD_START
  STA SND_CMD
  JSR VDP_INT_ON
.t_rel:                        ; buttons released...
  JSR TITLE_FRAME
  LDA JOYC
  AND #BTN_MASK
  BNE .t_rel
.t_press:                      ; ...then button 1 = continue, button 2 = a new house
  JSR TITLE_FRAME
  LDA SND_BUSY                 ; the tune again
  BNE .t_tn
  STZ SONG
  LDA #CMD_START
  STA SND_CMD
.t_tn:
  LDA JNEW
  AND #BTN_MASK
  BEQ .t_press
  LDX FRAME_CNT                ; the moment you press seeds the random generator
  CPX #0
  BNE .t_sd
  INX
.t_sd:
  STX RND
  AND #J_B2
  BNE .t_new
  LDA HASSAVE                  ; button 1: the saved house, if any
  BEQ .t_new1
  LDA #CMD_GAME
  STA SND_CMD
  JMP CONTINUE
.t_new1:
  JMP NEW_HOUSE
.t_new:
  LDA HASSAVE                  ; button 2 with a saved house: press it twice
  BEQ .t_new1
  LDA CONFIRM
  BNE .t_new1
  INC CONFIRM
  JSR VDP_INT_OFF
  LDA #<TXT_SURE
  STA TP
  LDA #>TXT_SURE
  STA TP+1
  JSR PRINT
  JSR VDP_INT_ON
  BRA .t_press

; row 18 of the title: the saved house (VDP interrupt off)
TITLE_STATUS:
  LDA SV_OK
  BNE .ts_sd
  LDA #<TXT_NOSD
  STA TP
  LDA #>TXT_NOSD
  STA TP+1
  JSR PRINT
  BRA .ts_b
.ts_sd:
  LDA HASSAVE
  BEQ .ts_b
  LDX #18
  LDY #3
  JSR NT_XY
  LDA #<TXT_HDAY
  LDY #>TXT_HDAY
  JSR PUTS
  LDA S_DAY
  STA NUM16
  LDA S_DAY+1
  STA NUM16+1
  JSR PUT_NUM16
  LDA #<TXT_HBEST
  LDY #>TXT_HBEST
  JSR PUTS
  LDA S_BEST
  STA NUM16
  STZ NUM16+1
  JSR PUT_NUM16
  LDA #<TXT_HOF10
  LDY #>TXT_HOF10
  JSR PUTS
.ts_b:
  LDA #<TXT_BTN2              ; the buttons
  STA TP
  LDA #>TXT_BTN2
  STA TP+1
  LDA HASSAVE
  BNE .ts_p
  LDA #<TXT_BTN1
  STA TP
  LDA #>TXT_BTN1
  STA TP+1
.ts_p:
  JMP PRINT

; one frame of the title: Six waves, Byte sits beside him
TITLE_FRAME:
  JSR VDP_INT_OFF
  JSR READ_JOY
  JSR JOY_EDGE
  LDA #116
  STA SIXX
  LDA #128
  STA SIXY
  LDA #PO_WAVE1                ; the arm goes up and down
  LDX FRAME_CNT
  CPX #128
  BCC .tf_w
  LDA #PO_FRONT
.tf_w:
  BIT FRAME_CNT
  BVC .tf_w2
  CMP #PO_WAVE1
  BNE .tf_w2
  LDA #PO_WAVE2
.tf_w2:
  JSR SAT_SIX
  LDA #140
  STA CATX
  LDA #128
  STA CATY
  LDA #PC_SIT
  STA CATP
  JSR SAT_CAT
  LDX SPRN                     ; Byte grey on the black of the title
  LDA #14
  STA SAT_BUFFER-1,X
  JSR SAT_END
  JMP VDP_INT_ON


; ===============================================================
;  A NEW HOUSE: Six moves in
; ===============================================================
NEW_HOUSE:
  LDA #CMD_GAME
  STA SND_CMD
  LDX #ST_LEN-1               ; everything to 0, then the start values
.nh_z:
  STZ STATE,X
  DEX
  BPL .nh_z
  LDX #NEW_N-1
.nh_v:
  LDY NEW_OFF,X
  LDA NEW_VAL,X
  STA STATE,Y
  DEX
  BPL .nh_v
.nh_p:                         ; his character, at random
  JSR NEXT_RND
  AND #7
  CMP #6
  BCS .nh_p
  STA S_PERS
  LDX #4
.nh_d:
  LDA DECAY_P,X
  STA S_DCNT,X
  DEX
  BPL .nh_d
  LDA #2
  STA SIXF
  LDA #240                     ; outside, by the mailbox
  STA SIXX
  LDA #2
  STA CATF
  LDA #196
  STA CATX
  LDA #240                     ; Byte waits at the door
  STA CATX
  JSR HOUSE_START
  LDA #1                       ; the visit (TOUR) from the door
  STA TOURI
  JMP GAME_LOOP

; ===============================================================
;  CONTINUE: the house from the SD
; ===============================================================
CONTINUE:
  LDA S_FLR
  CMP #3
  BCC .co_f
  LDA #2
.co_f:
  STA SIXF
  LDA S_X
  CMP #LADX
  BCS .co_x
  LDA #LADX
.co_x:
  STA SIXX
  LDA SIXF
  STA CATF
  LDA SIXX
  EOR #$80
  AND #$7F
  CLC
  ADC #48
  STA CATX
  JSR HOUSE_START
  LDA #TX_BACK
  JSR SPEAK
  LDA #90
  STA WAVET
  STZ RPROP
  JMP GAME_LOOP

; the house on the screen and everything ready for the loop
HOUSE_START:
  LDX SIXF
  LDA FLOOR_Y,X
  STA SIXY
  LDX CATF
  LDA FLOOR_Y,X
  STA CATY
  LDA SIXF
  STA TGTF
  LDA SIXX
  STA TGTX
  LDA CATF
  STA CTGF
  LDA CATX
  STA CTGX
  LDA #2
  STA APH
  LDA #A_IDLE
  STA ACT
  STA LASTA
  LDA #$FF
  STA NEXTA
  STA OBJA
  STZ MENU
  STZ SPKT
  STZ WAVET
  STZ SLEEPING
  STZ SAVEREQ
  STZ GOGAME
  STZ TOURI
  STZ LOWN
  STZ CATA
  LDA #60
  STA CATT
  LDA #PC_SIT
  STA CATP
  LDA #$FF
  STA CATNEXT
  LDA #200
  STA MEOWT
  LDA #60
  STA CLKF
  STZ FACEI
  JSR MOOD_CALC
  JSR VDP_INT_OFF
  JSR REDRAW
  JMP VDP_INT_ON


; ===============================================================
;  GAME LOOP: one pass = one frame
; ===============================================================
GAME_LOOP:
  JSR VDP_INT_OFF              ; waits for the vblank and frees the VDP
  JSR READ_JOY
  JSR JOY_EDGE
  JSR NEXT_RND
  LDA TOURI                    ; the clock waits for the end of the visit
  BNE .gl_c
  JSR CLOCK
.gl_c:
  JSR SIX
  JSR CAT
  JSR MENU_RUN
  JSR OBJ_ANIM
  JSR PANEL
  JSR BUILD_SAT
WEND:
  JSR VDP_INT_ON
  LDA SAVEREQ                  ; the hourly save
  BEQ .gl_g
  STZ SAVEREQ
  JSR ST_SAVE
.gl_g:
  LDA GOGAME                   ; HI-LO BITS at the computer
  BEQ GAME_LOOP
  STZ GOGAME
  JSR HILO
  JSR VDP_INT_OFF
  JSR REDRAW
  JSR VDP_INT_ON
  JSR ACT_END
  BRA GAME_LOOP

; the two joysticks together, the new presses
JOY_EDGE:
  LDA P_JOY
  ORA P_JOY+1
  STA JOYC
  LDA JPREV
  EOR #$FF
  AND JOYC
  STA JNEW
  LDA JOYC
  STA JPREV
  RTS


; ===============================================================
;  THE CLOCK: one game minute every 60 frames (15 asleep)
; ===============================================================
CLOCK:
  DEC CLKF
  BEQ .cl_m
  RTS
.cl_m:
  LDA #60
  LDX SLEEPING
  BEQ .cl_s
  LDA #15
.cl_s:
  STA CLKF
  INC TICKS
  LDA #D_CLOCK
  TSB DIRTY
  INC S_MIN
  LDA S_MIN
  CMP #60
  BCC MINUTE
  STZ S_MIN
  INC S_HOUR
  LDA #1                       ; every hour: save
  STA SAVEREQ
  LDA S_HOUR
  CMP #24
  BCC .cl_h
  STZ S_HOUR                   ; midnight: a new day
  INC S_DAY
  BNE .cl_d
  INC S_DAY+1
.cl_d:
  LDA S_FLOWER                 ; the flowers wilt
  CMP #2
  BCC .cl_h
  DEC S_FLOWER
  JSR SET_VASE
.cl_h:
  JSR SET_WINDOWS
  JSR WAKE_CHECK
  ; fall into MINUTE

; ---------------------------------------------------------------
;  MINUTE: the needs drop, the activity gives, health and mood
; ---------------------------------------------------------------
MINUTE:
  LDX #4                       ; the five needs drop, every one at its pace
.mi_d:
  LDA SLEEPING                 ; asleep: no tiredness, and half the hunger, thirst...
  BEQ .mi_aw
  CPX #N_REST
  BEQ .mi_n
  LDA S_MIN
  LSR A
  BCS .mi_n
.mi_aw:
  DEC S_DCNT,X
  BNE .mi_n
  LDY S_PERS                   ; his weak point drops faster
  LDA PERS_NEED,Y
  STA T7
  LDA DECAY_P,X
  CPX T7
  BNE .mi_p
  LSR A
  ADC #0
.mi_p:
  STA S_DCNT,X
  LDA NEED,X
  BEQ .mi_n
  DEC NEED,X
.mi_n:
  DEX
  BPL .mi_d
  LDA APH                      ; the activity
  CMP #1
  BNE .mi_h
  LDY ACT
  LDX ACT_N1,Y
  LDA ACT_D1,Y
  JSR NEED_ADD
  LDY ACT
  LDX ACT_N2,Y
  BMI .mi_t
  LDA ACT_D2,Y
  JSR NEED_ADD
.mi_t:
  LDX S_PERS                   ; his favourite one: more fun
  LDA PERS_FAV,X
  CMP ACT
  BNE .mi_tm
  LDX #N_FUN
  LDA #2
  JSR NEED_ADD
.mi_tm:
  LDA ACT
  CMP #A_SLEEP                 ; sleep ends by itself (WAKE_CHECK)
  BEQ .mi_h
  DEC ATIME
  BNE .mi_h
  JSR ACT_END
.mi_h:
  ; ---- health: low needs take it, all right gives it back
  STZ T0
  LDX #3
.mi_l:
  LDA NEED,X
  CMP #40
  BCS .mi_l1
  INC T0
.mi_l1:
  DEX
  BPL .mi_l
  LDA T0
  BEQ .mi_good
  LDA S_MIN
  AND #3
  BNE .mi_hd
  LDA NEED+N_HEALTH
  SEC
  SBC T0
  BCS .mi_hs
  LDA #0
.mi_hs:
  STA NEED+N_HEALTH
  BRA .mi_hd
.mi_good:
  LDA S_MIN
  AND #3
  BNE .mi_hd
  LDA SLEEPING                 ; asleep or every 8 minutes with all right
  BNE .mi_hp
  LDA S_MIN
  AND #7
  BNE .mi_hd
.mi_hp:
  LDX #N_HEALTH
  LDA #1
  JSR NEED_ADD
.mi_hd:
  ; ---- joy and annoyance fade, Byte gets hungry
  LDA S_MIN
  LSR A
  BCC .mi_j
  LDA S_HAPPY
  BEQ .mi_c
  DEC S_HAPPY
.mi_c:
  LDA S_CATF
  BEQ .mi_j
  DEC S_CATF
.mi_j:
  LDA S_ANNOY
  SEC
  SBC #2
  BCS .mi_a
  LDA #0
.mi_a:
  STA S_ANNOY
  JSR CAT_NEAR                 ; Byte near and happy: Six has fun
  BCC .mi_cn
  LDA S_MIN
  AND #3
  BNE .mi_cn
  LDX #N_FUN
  LDA #1
  JSR NEED_ADD
.mi_cn:
  JSR MOOD_CALC
  JMP LOW_TALK

; X = need, A = signed change: the need stays in 0-255
NEED_ADD:
  CMP #0
  BMI .na_m
  CLC
  ADC NEED,X
  BCC .na_s
  LDA #$FF
  BRA .na_s
.na_m:
  CLC
  ADC NEED,X
  BCS .na_s
  LDA #0
.na_s:
  STA NEED,X
  LDA #D_BARS
  TSB DIRTY
  RTS

; the mood: the four needs, fun, joy, annoyance, Byte
MOOD_CALC:
  LDA NEED+N_FOOD
  CLC
  ADC NEED+N_DRINK
  STA T0
  LDA #0
  ROL A
  STA T1
  LDA T0
  CLC
  ADC NEED+N_REST
  STA T0
  BCC .mc_1
  INC T1
.mc_1:
  CLC
  ADC NEED+N_CLEAN
  STA T0
  BCC .mc_2
  INC T1
.mc_2:
  LSR T1                       ; / 4
  ROR T0
  LSR T1
  ROR T0
  LDA T0
  CLC
  ADC NEED+N_FUN
  ROR A                        ; (average of the four and fun)
  STA T0
  LDA S_HAPPY
  LSR A
  CLC
  ADC T0
  BCC .mc_3
  LDA #$FF
.mc_3:
  STA T0
  LDA S_ANNOY
  LSR A
  STA T1
  LDA T0
  SEC
  SBC T1
  BCS .mc_4
  LDA #0
.mc_4:
  STA T0
  LDA S_CATF                   ; a hungry cat makes him sad
  CMP #40
  BCS .mc_5
  LDA T0
  SEC
  SBC #32
  BCS .mc_4b
  LDA #0
.mc_4b:
  STA T0
.mc_5:
  LDA T0
  STA MOOD
  LDX #3                       ; the face
  LDA NEED+N_HEALTH
  CMP #64
  BCC .mc_f
  LDX #0
  LDA MOOD
  CMP #160
  BCS .mc_f
  INX
  CMP #90
  BCS .mc_f
  INX
.mc_f:
  CPX FACEI
  BEQ .mc_e
  STX FACEI
  LDA #D_HUD
  TSB DIRTY
.mc_e:
  RTS

; a need goes low: Six says so (once, until it is all right again)
LOW_TALK:
  LDX #5
.lt_l:
  LDA NEED,X
  CMP #48
  BCS .lt_ok
  LDA BITS,X
  BIT LOWN
  BNE .lt_n
  TSB LOWN
  LDA SLEEPING
  BNE .lt_n
  LDA LOW_TX,X
  JMP SPEAK
.lt_ok:
  CMP #96
  BCC .lt_n
  LDA BITS,X
  TRB LOWN
.lt_n:
  DEX
  BPL .lt_l
  RTS

; every hour: the alarm clock in the morning, the end of a nap
WAKE_CHECK:
  LDA APH
  CMP #1
  BNE .wc_e
  LDA ACT
  CMP #A_SLEEP
  BNE .wc_e
  JSR IS_NIGHT
  BCS .wc_e
  LDX S_PERS
  LDA S_HOUR
  CMP WAKE_H,X
  BNE .wc_nap
  LDA #W_RING                  ; the alarm clock rings
  LDX #0
  JSR SFX_WHISTLE
  LDA #90                      ; the clock shakes for 1.5 s
  STA ALARMT
  LDA #O_CLOCK
  STA OBJA
  JMP ACT_END
.wc_nap:
  LDA NEED+N_REST
  CMP #240
  BCC .wc_e
  JMP ACT_END
.wc_e:
  RTS

; C = 1 at night (from his bedtime to his alarm clock)
IS_NIGHT:
  LDX S_PERS
  LDA S_HOUR
  CMP BED_H,X
  BCS .in_y
  CMP WAKE_H,X
  BCC .in_y
  CLC
  RTS
.in_y:
  SEC
  RTS


; ===============================================================
;  THE HOUSE ON THE SD (sectors 2 and 3 of zone 39, in turn)
; ===============================================================
; SV_BUF: "MVSV",1,zone,2 (a house),0,0,0, counter (2), ..., the state from byte 16, sum at 510
ST_SAVE:
  LDA SV_OK
  BNE .ss_go
  SEC
  RTS
.ss_go:
  LDA SIXF
  STA S_FLR
  LDA SIXX
  STA S_X
  LDX #0
.ss_z:
  STZ SV_BUF,X
  STZ SV_BUF+256,X
  INX
  BNE .ss_z
  LDX #5
.ss_h:
  LDA REC_HDR,X
  STA SV_BUF,X
  DEX
  BPL .ss_h
  LDA #2
  STA SV_BUF+6
  INC ST_CNT
  BNE .ss_c
  INC ST_CNT+1
.ss_c:
  LDA ST_CNT
  STA SV_BUF+10
  LDA ST_CNT+1
  STA SV_BUF+11
  LDX #ST_LEN-1
.ss_s:
  LDA STATE,X
  STA SV_BUF+16,X
  DEX
  BPL .ss_s
  JSR REC_SUM
  LDA REC_SL
  STA SV_BUF+510
  LDA REC_SH
  STA SV_BUF+511
  LDA ST_OLD
  CLC
  ADC #ST_SEC
  STA SV_SEC
  LDA #1
  JSR SV_CALL
  BCS .ss_e
  LDA ST_OLD
  EOR #1
  STA ST_OLD
  LDA #1
  STA HASSAVE
  CLC
.ss_e:
  RTS

; at RESET: the newer valid copy of the house
ST_LOAD:
  STZ HASSAVE
  STZ ST_OLD
  STZ ST_CNT
  STZ ST_CNT+1
  LDA SV_OK
  BEQ .sl_e
  LDA #0
.sl_l:
  STA T6                       ; copy 0 / 1
  CLC
  ADC #ST_SEC
  STA SV_SEC
  LDA #0
  JSR SV_CALL
  BCS .sl_n
  JSR ST_VALID
  BCS .sl_n
  LDA HASSAVE                  ; both: the higher counter
  BEQ .sl_take
  LDA SV_BUF+11
  CMP ST_CNT+1
  BCC .sl_n
  BNE .sl_take
  LDA SV_BUF+10
  CMP ST_CNT
  BCC .sl_n
  BEQ .sl_n
.sl_take:
  LDX #ST_LEN-1
.sl_c:
  LDA SV_BUF+16,X
  STA STATE,X
  DEX
  BPL .sl_c
  LDA SV_BUF+10
  STA ST_CNT
  LDA SV_BUF+11
  STA ST_CNT+1
  LDA T6                       ; the next write goes to the other copy
  EOR #1
  STA ST_OLD
  LDA #1
  STA HASSAVE
.sl_n:
  LDA T6
  INC A
  CMP #2
  BCC .sl_l
.sl_e:
  RTS

; SV_BUF is a house of this game? C = 0 yes
ST_VALID:
  LDX #5
.sv_h:
  LDA SV_BUF,X
  CMP REC_HDR,X
  BNE .sv_no
  DEX
  BPL .sv_h
  LDA SV_BUF+6
  CMP #2
  BNE .sv_no
  JSR REC_SUM
  LDA REC_SL
  CMP SV_BUF+510
  BNE .sv_no
  LDA REC_SH
  CMP SV_BUF+511
  BNE .sv_no
  CLC
  RTS
.sv_no:
  SEC
  RTS

; hooks of lib_records.asm (its table is not used)
REC_ONEPL = 1
REC_XY = NT_XY
REC_CLS:
  JMP CLEAR_NT
REC_SND:
  RTS
REC_NAME:  .byte "LITTLE 6502 GUY "
REC_HEAD:  .byte "HOUSES",0
REC_XLBL:  .byte "DAY ",0

; ===============================================================
;  SIX: walking, the ladder, doing things, choosing what to do
; ===============================================================
CLIMBF      = $90      ; 1 = Six is on the ladder between two floors
CATCL       = $91      ; 1 = Byte is on the ladder
MUSICON     = $92      ; 1 = a record is playing
ALARMT      = $93      ; frames the alarm clock still rings
CATDY       = $94      ; Byte: height on the sofa / the bed
TMPF        = $95
TOURI       = $98      ; the first visit of a new house: stop + 1 (0 = no visit)
TPOSE       = $99      ; pose of Six at a stop of the visit ($FF = waving)
ENVO        = $9A      ; instrument of the tune: 0 organ, 4 piano (the records)

SIX:
  LDA TOURI                    ; a new house: first he looks around
  BEQ .sx_w
  JMP TOUR
.sx_w:
  LDA WAVET                    ; a reaction: he stands and waves
  BEQ .sx_go
  DEC WAVET
  BNE .sx_r
  STZ RPROP
.sx_r:
  RTS
.sx_go:
  LDA APH
  BEQ SIX_MOVE
  CMP #1
  BNE .sx_c
  JMP SIX_DOING
.sx_c:
  JMP CHOOSE

; going: to the ladder, up or down, then to the place
SIX_MOVE:
  LDA FRAME_CNT                ; 3 pixels every 4 frames
  AND #3
  BNE .sm_1
  RTS
.sm_1:
  LDA SIXF
  CMP TGTF
  BEQ .sm_same
  LDA SIXX
  CMP #LADX
  BEQ .sm_cl
  LDA #LADX
  JMP SIX_STEP
.sm_cl:
  LDA #1
  STA CLIMBF
  LDX SIXF                     ; the next floor
  LDA TGTF
  CMP SIXF
  BCS .sm_dn
  DEX
  BRA .sm_y
.sm_dn:
  INX
.sm_y:
  STX TMPF
  LDA FLOOR_Y,X
  CMP SIXY
  BEQ .sm_arr
  BCS .sm_d
  DEC SIXY
  BRA .sm_s
.sm_d:
  INC SIXY
.sm_s:
  INC WALKC
  LDA WALKC
  AND #7
  BNE .sm_e
  LDA #W_RUNG
  LDX #0
  JMP SFX_WHISTLE
.sm_arr:
  LDA TMPF
  STA SIXF
  STZ CLIMBF
.sm_e:
  RTS
.sm_same:
  STZ CLIMBF
  LDA SIXX
  CMP TGTX
  BEQ .sm_here
  LDA TGTX
  JMP SIX_STEP
.sm_here:
  JMP ACT_BEGIN

; one pixel towards x = A, the steps
SIX_STEP:
  CMP SIXX
  BCC .ss_l
  INC SIXX
  STZ FACE
  BRA .ss_s
.ss_l:
  DEC SIXX
  LDA #1
  STA FACE
.ss_s:
  INC WALKC
  LDA WALKC
  AND #7
  BNE .ss_e
  LDA #W_STEP
  LDX #0
  LDY SIXX
  BPL .ss_p
  INX
.ss_p:
  JMP SFX_WHISTLE
.ss_e:
  RTS

; ---------------------------------------------------------------
;  A = activity: he goes there (what is missing changes it)
; ---------------------------------------------------------------
ACT_START:
  CMP #A_EAT
  BNE .as_1
  LDX S_FRIDGE
  BNE .as_ok
  LDA #TX_NOFOOD
  JSR SPEAK
  LDA #A_COMPLAIN
  BRA .as_ok
.as_1:
  CMP #A_DRINK
  BNE .as_2
  LDX S_WATER
  BNE .as_ok
  LDA #TX_NOWATER
  JSR SPEAK
  LDA #A_COMPLAIN
  BRA .as_ok
.as_2:
  CMP #A_BALL
  BNE .as_ok
  LDX S_BALL
  BNE .as_ok
  LDA #A_IDLE
.as_ok:
  STA ACT
  TAY
  LDA ACT_F,Y
  STA TGTF
  LDA ACT_X,Y
  STA TGTX
  CPY #A_IDLE                  ; somewhere: one of the places to stand
  BNE .as_g
  JSR NEXT_RND
  AND #7
  TAX
  LDA IDLE_F,X
  STA TGTF
  LDA IDLE_X,X
  STA TGTX
.as_g:
  STZ APH
  RTS

; a request: what he does now stops
INTERRUPT:
  PHA
  LDA APH
  CMP #1
  BNE .it_s
  JSR ACT_END
.it_s:
  STZ WAVET
  PLA
  JMP ACT_START

; ---------------------------------------------------------------
;  he is there: the activity begins
; ---------------------------------------------------------------
ACT_BEGIN:
  LDA #1
  STA APH
  LDY ACT
  LDA ACT_MIN,Y
  STA ATIME
  LDA #30
  STA SNDT
  STZ ANIMT
  LDA ACT_OBJ,Y
  STA OBJA
  BMI .ab_n
  TAX
  LDA #1
  JSR OBJ_SET
.ab_n:
  LDA ACT
  CMP #A_EAT
  BNE .ab_1
  DEC S_FRIDGE
  LDA #D_HUD
  TSB DIRTY
  RTS
.ab_1:
  CMP #A_DRINK
  BNE .ab_2
  DEC S_WATER
  LDA #D_HUD
  TSB DIRTY
  LDA #S_FRDOOR
  LDX #0
  JMP SFX_BOOM
.ab_2:
  CMP #A_SLEEP
  BNE .ab_3
  LDA #1
  STA SLEEPING
  JSR IS_NIGHT
  BCC .ab_e
  LDA #TX_NIGHT
  JMP SPEAK
.ab_3:
  CMP #A_MUSIC
  BNE .ab_4
  JSR SONG_PICK
  LDA #1
  STA MUSICON
  RTS
.ab_4:
  CMP #A_HILO
  BNE .ab_e
  LDA #1
  STA GOGAME
.ab_e:
  RTS

; a record: the first one or one of those he was given
SONG_PICK:
  JSR NEXT_RND
  AND #3
  CMP S_RECS
  BCC .sp_s
  BEQ .sp_s
  LDA S_RECS
.sp_s:
  INC A
  STA SONG
  LDA #CMD_START
  STA SND_CMD
  RTS

; ---------------------------------------------------------------
;  the activity is over (or stopped)
; ---------------------------------------------------------------
ACT_END:
  LDA OBJA
  BMI .ae_o
  TAX
  LDA #0
  JSR OBJ_SET
.ae_o:
  LDA #$FF
  STA OBJA
  LDA ACT
  CMP #A_SLEEP
  BNE .ae_1
  STZ SLEEPING
  LDA #60
  STA CLKF
  LDA #TX_MORNING
  JSR SPEAK
  BRA .ae_x
.ae_1:
  CMP #A_MUSIC
  BNE .ae_2
  STZ MUSICON
  LDA #CMD_GAME
  STA SND_CMD
  BRA .ae_x
.ae_2:
  CMP #A_LETTER
  BNE .ae_x
  LDA ATIME                    ; only a letter finished
  BNE .ae_x
  JSR LETTER_NEW
  LDA #TX_WROTE
  JSR SPEAK
  LDA #W_BELL
  LDX #1
  JSR SFX_WHISTLE
.ae_x:
  LDA ACT
  STA LASTA
  LDA #2
  STA APH
  RTS

; ---------------------------------------------------------------
;  doing it: its sounds, the record again
; ---------------------------------------------------------------
SIX_DOING:
  LDA MUSICON
  BEQ .sd_s
  LDA SND_BUSY
  BNE .sd_s
  JSR SONG_PICK
.sd_s:
  DEC SNDT
  BNE .sd_e
  LDY ACT
  JSR NEXT_RND
  AND #15
  CLC
  ADC ACT_SNDP,Y
  STA SNDT
  LDA ACT_SND,Y
  BEQ .sd_e
  LDX #0
  LDY SIXX
  BPL .sd_p
  INX
.sd_p:
  CMP #$80
  BCS .sd_n
  CMP #W_TYPE                  ; the typewriter: a bell now and then
  BNE .sd_w
  PHA
  JSR NEXT_RND
  CMP #24
  PLA
  BCS .sd_w
  LDA #W_BELL
.sd_w:
  JMP SFX_WHISTLE
.sd_n:
  AND #$7F
  JMP SFX_BOOM
.sd_e:
  RTS

; ---------------------------------------------------------------
;  CHOOSE: nothing to do, what now?
; ---------------------------------------------------------------
CHOOSE:
  LDA NEXTA                    ; something asked
  CMP #$FF
  BEQ .ch_a
  LDX #$FF
  STX NEXTA
  JMP ACT_START
.ch_a:
  LDA NEED+N_DRINK             ; what he really needs
  CMP #50
  BCS .ch_1
  LDA #A_DRINK
  JMP ACT_START
.ch_1:
  LDA NEED+N_FOOD
  CMP #50
  BCS .ch_2
  LDA #A_EAT
  JMP ACT_START
.ch_2:
  LDA NEED+N_REST
  CMP #40
  BCC .ch_sl
  LDA NEED+N_HEALTH
  CMP #64
  BCC .ch_sk
  JSR IS_NIGHT
  BCC .ch_3
.ch_sl:
  LDA #A_SLEEP
  JMP ACT_START
.ch_sk:
  LDA #TX_SICKBED
  JSR SPEAK
  BRA .ch_sl
.ch_3:
  LDA NEED+N_CLEAN
  CMP #40
  BCS .ch_4
.ch_bath:
  LDA #A_BATH
  JMP ACT_START
.ch_4:
  LDX S_PERS                   ; meals
  LDA S_HOUR
  CMP WAKE_H,X
  BEQ .ch_meal
  CMP #12
  BEQ .ch_meal
  CMP #19
  BNE .ch_5
.ch_meal:
  LDA NEED+N_FOOD
  CMP #200
  BCS .ch_5
  LDA #A_EAT
  JMP ACT_START
.ch_5:
  LDA NEED+N_DRINK
  CMP #140
  BCS .ch_6
  LDA #A_DRINK
  JMP ACT_START
.ch_6:
  LDX S_PERS                   ; the bath in the morning
  LDA WAKE_H,X
  INC A
  CMP S_HOUR
  BNE .ch_7
  LDA NEED+N_CLEAN
  CMP #220
  BCC .ch_bath
.ch_7:
  LDA S_HOUR                   ; a letter in the evening, one a day
  CMP #20
  BCC .ch_8
  LDA S_LETD
  CMP S_DAY
  BEQ .ch_8
  JSR NEXT_RND
  CMP #64
  BCS .ch_8
  LDA #A_LETTER
  JMP ACT_START
.ch_8:
  LDA NEED+N_FUN               ; bored: his favourite
  CMP #40
  BCS .ch_9
  LDX S_PERS
  LDA PERS_FAV,X
  JMP ACT_START
.ch_9:
  JSR NEXT_RND                 ; free time: by his character, not twice the same
  AND #7
  STA T0
  LDA S_PERS
  ASL A
  ASL A
  ASL A
  ORA T0
  TAX
  LDA FREE_T,X
  CMP LASTA
  BNE .ch_go
  LDA #A_IDLE
.ch_go:
  JMP ACT_START


; ===============================================================
;  BYTE THE CAT
; ===============================================================
CAT:
  LDA CATA
  BNE .ct_still
  JMP CAT_MOVE
.ct_still:
  LDA FRAME_CNT
  AND #3
  BNE .ct_m
  DEC CATT
  BNE .ct_m
  LDA CATA                     ; done: if he was eating, the bowl
  CMP #3
  BNE .ct_ch
  LDA S_CATF
  CLC
  ADC #150
  BCC .ct_f
  LDA #$FF
.ct_f:
  STA S_CATF
  LDA S_BOWL
  BEQ .ct_b
  DEC S_BOWL
.ct_b:
  JSR SET_BOWL
  LDA #D_HUD
  TSB DIRTY
.ct_ch:
  JSR CAT_CHOOSE
.ct_m:
  ; ---- hungry with the bowl empty: he meows
  LDA S_CATF
  CMP #60
  BCS .ct_e
  LDA S_BOWL
  BNE .ct_e
  DEC MEOWT
  BNE .ct_e
  LDA #240
  STA MEOWT
  LDA #W_MEOW
  LDX #1
  JSR SFX_WHISTLE
  LDA SPKT
  BNE .ct_e
  LDA #TX_CATHUNGRY
  JMP SPEAK
.ct_e:
  RTS

; what Byte does next
CAT_CHOOSE:
  STZ CATDY
  LDX CATF                     ; down from the sofa or the bed
  LDA FLOOR_Y,X
  STA CATY
  LDA SLEEPING                 ; Six asleep: at the foot of the bed
  BEQ .cc_1
  LDA #0
  LDX #112
  LDY #2
  STY CATNEXT
  LDY #250
  STY CATT
  LDY #$FA
  STY CATDY
  BRA .cc_go
.cc_1:
  LDA S_CATF                   ; hungry and something in the bowl
  CMP #120
  BCS .cc_2
  LDA S_BOWL
  BEQ .cc_2
  LDA #3
  STA CATNEXT
  LDA #80
  STA CATT
  LDA #2
  LDX #40
  BRA .cc_go
.cc_2:
  JSR NEXT_RND
  AND #7
  CMP #3
  BCS .cc_3
  LDA #1                       ; near Six
  STA CATNEXT
  LDA #60
  STA CATT
  LDA SIXX
  CLC
  ADC #22
  CMP #210
  BCC .cc_x
  LDA SIXX
  SEC
  SBC #22
.cc_x:
  TAX
  LDA SIXF
  BRA .cc_go
.cc_3:
  CMP #5
  BCS .cc_4
  LDA #2                       ; a nap on the sofa
  STA CATNEXT
  LDA #200
  STA CATT
  LDA #$F6
  STA CATDY
  LDA #2
  LDX #158
  BRA .cc_go
.cc_4:
  LDA #1                       ; somewhere
  STA CATNEXT
  LDA #100
  STA CATT
  JSR NEXT_RND
  AND #7
  TAY
  LDA IDLE_X,Y
  CLC
  ADC #12
  TAX
  LDA IDLE_F,Y
.cc_go:
  STA CTGF
  STX CTGX
  STZ CATA
  RTS

; walking like Six, one pixel a frame
CAT_MOVE:
  LDA CATF
  CMP CTGF
  BEQ .cm_same
  LDA CATX
  CMP #LADX
  BEQ .cm_cl
  LDA #LADX
  JMP CAT_STEP
.cm_cl:
  LDA #1
  STA CATCL
  LDA #PC_SIT
  STA CATP
  LDX CATF
  LDA CTGF
  CMP CATF
  BCS .cm_dn
  DEX
  BRA .cm_y
.cm_dn:
  INX
.cm_y:
  LDA FLOOR_Y,X
  CMP CATY
  BEQ .cm_arr
  BCS .cm_d
  DEC CATY
  RTS
.cm_d:
  INC CATY
  RTS
.cm_arr:
  STX CATF
  STZ CATCL
  RTS
.cm_same:
  STZ CATCL
  LDA CATX
  CMP CTGX
  BEQ .cm_here
  LDA CTGX
  JMP CAT_STEP
.cm_here:
  LDA CATNEXT                  ; there: sit, sleep or eat
  STA CATA
  LDX CATF
  LDA FLOOR_Y,X
  CLC
  ADC CATDY
  STA CATY
  LDX CATA
  LDA CAT_POSE,X
  STA CATP
  RTS

; one pixel towards x = A
CAT_STEP:
  INC CATW
  CMP CATX
  BCC .cs_l
  INC CATX
  LDA #PC_WALKR1
  BRA .cs_p
.cs_l:
  DEC CATX
  LDA #PC_WALKL1
.cs_p:
  LDX CATW
  CPX #0
  PHA
  TXA
  AND #8
  BEQ .cs_1
  PLA
  INC A
  STA CATP
  RTS
.cs_1:
  PLA
  STA CATP
  RTS

; C = 1 if Byte is fed and near Six
CAT_NEAR:
  LDA S_CATF
  CMP #100
  BCC .cn_n
  LDA CATF
  CMP SIXF
  BNE .cn_n
  LDA CATX
  SEC
  SBC SIXX
  BCS .cn_p
  EOR #$FF
  INC A
.cn_p:
  CMP #40
  BCS .cn_n
  SEC
  RTS
.cn_n:
  CLC
  RTS

; ---------------------------------------------------------------
;  TOUR: a new house. Six knocks, walks through the six rooms,
;  thinks it over and moves in (button 1 skips it)
; ---------------------------------------------------------------
TOUR:
  LDA JNEW                     ; no menu during the visit
  STZ JNEW
  AND #J_B1
  BEQ .tu_w
  LDA CLIMBF                   ; (not halfway up the ladder)
  BEQ .tu_end
.tu_w:
  LDA WAVET                    ; he stops and looks
  BEQ .tu_go
  DEC WAVET
  RTS
.tu_go:
  STZ RPROP
  LDA SIXF
  CMP TGTF
  BNE .tu_mv
  LDA SIXX
  CMP TGTX
  BNE .tu_mv
  LDX TOURI                    ; at stop TOURI-1: what he says
  LDA TOUR_TX-1,X
  BMI .tu_end
  JSR SPEAK
  LDX TOURI
  LDA TOUR_PR-1,X
  STA RPROP
  LDA TOUR_PO-1,X
  STA TPOSE
  LDA TOUR_W-1,X
  STA WAVET
  LDA TOUR_F,X                 ; the next stop
  STA TGTF
  LDA TOUR_X,X
  STA TGTX
  INC TOURI
  LDA #2
  STA APH
  RTS
.tu_mv:
  STZ APH
  JMP SIX_MOVE
.tu_end:                       ; he stays: the moving-in tune
  STZ TOURI
  LDA #2
  STA APH
  LDA #5
  STA SONG
  LDA #CMD_START
  STA SND_CMD
  LDA #TX_HELLO
  JSR SPEAK
  LDA #PR_HEART
  STA RPROP
  LDA #120
  STA WAVET
  RTS

; ===============================================================
;  THE MENU (rows 22-23): button 1 opens it and confirms,
;  LEFT / RIGHT choose, button 2 goes back, UP = "please"
; ===============================================================
M_MAIN      = 1
M_GIFT      = 2
M_ASK       = 3
M_LET       = 4

MENU_RUN:
  LDA MENU
  BNE .mr_open
  LDA JNEW                     ; closed: button 1 opens it
  AND #J_B1
  BEQ .mr_e
  LDA #M_MAIN
  JSR MENU_OPEN
  LDA #W_MENU
  LDX #2
  JMP SFX_WHISTLE
.mr_e:
  RTS
.mr_open:
  LDA JNEW
  BIT #J_LEFT
  BEQ .mr_r
  LDA MSEL
  BNE .mr_l1
  LDA MITEMS
.mr_l1:
  DEC A
  STA MSEL
  BRA .mr_moved
.mr_r:
  BIT #J_RIGHT
  BEQ .mr_u
  LDA MSEL
  INC A
  CMP MITEMS
  BCC .mr_r1
  LDA #0
.mr_r1:
  STA MSEL
.mr_moved:
  LDA #D_ROW23
  TSB DIRTY
  LDA #W_MENU
  LDX #2
  JMP SFX_WHISTLE
.mr_u:
  BIT #(J_UP|J_DOWN)
  BEQ .mr_b2
  LDX MENU
  CPX #M_ASK
  BNE .mr_b2
  LDA PLEASE
  EOR #1
  STA PLEASE
  LDA #D_ROW22
  TSB DIRTY
  RTS
.mr_b2:
  LDA JNEW
  BIT #J_B2
  BEQ .mr_b1
  LDA MENU                     ; back: a list goes back to the main menu, the main menu closes
  CMP #M_MAIN
  BEQ MENU_CLOSE
  LDA #M_MAIN
  JMP MENU_OPEN
.mr_b1:
  BIT #J_B1
  BEQ .mr_x
  LDA MENU
  CMP #M_MAIN
  BNE .mr_g
  JMP DO_MAIN
.mr_g:
  CMP #M_GIFT
  BNE .mr_a
  JMP DO_GIFT
.mr_a:
  CMP #M_ASK
  BNE .mr_lt
  JMP DO_ASK
.mr_lt:
  JMP DO_LETTER
.mr_x:
  RTS

; A = menu to open
MENU_OPEN:
  STA MENU
  STZ MSEL
  TAX
  LDA MENU_N-1,X
  STA MITEMS
  CPX #M_LET
  BNE .mo_d
  LDA NLET
  STA MITEMS
.mo_d:
  LDA #(D_ROW22|D_ROW23)
  TSB DIRTY
  RTS

MENU_CLOSE:
  STZ MENU
  STZ PLEASE
  LDA #(D_ROW22|D_ROW23)
  TSB DIRTY
  RTS

; ---------------------------------------------------------------
;  the main menu
; ---------------------------------------------------------------
DO_MAIN:
  LDA MSEL
  BNE .dm_1
  JSR MENU_CLOSE               ; BRING FOOD
  LDA S_FRIDGE
  CMP #9
  BCC .dm_f
  LDA #TX_FULL
  JMP SPEAK
.dm_f:
  LDA #9
  STA S_FRIDGE
  LDA #TX_FOOD
  BRA .dm_dlv
.dm_1:
  CMP #1
  BNE .dm_2
  JSR MENU_CLOSE               ; BRING WATER
  LDA S_WATER
  CMP #9
  BCC .dm_w
  LDA #TX_FULLW
  JMP SPEAK
.dm_w:
  LDA #9
  STA S_WATER
  LDA #TX_WATER
.dm_dlv:                       ; a delivery: the door bell, thanks
  PHA
  LDA #W_DING
  LDX #1
  JSR SFX_WHISTLE
  LDA #D_HUD
  TSB DIRTY
  LDX #10
  JSR JOY_ADD
  PLA
  LDX SLEEPING
  BEQ .dm_sp
  LDA #TX_DLVSLEEP
.dm_sp:
  JMP SPEAK
.dm_2:
  CMP #2
  BNE .dm_3
  JSR MENU_CLOSE               ; FEED BYTE
  LDA #6
  STA S_BOWL
  JSR SET_BOWL
  LDA #D_HUD
  TSB DIRTY
  LDA #W_MEOW
  LDX #1
  JSR SFX_WHISTLE
  LDA #TX_BOWL
  JMP SPEAK
.dm_3:
  CMP #3
  BNE .dm_4
  LDA #M_GIFT                  ; SEND A GIFT
  JMP MENU_OPEN
.dm_4:
  CMP #4
  BNE .dm_5
  STZ PLEASE                   ; ASK SIX
  LDA #M_ASK
  JMP MENU_OPEN
.dm_5:
  CMP #5
  BNE .dm_6
  JSR MENU_CLOSE               ; KNOCK ON THE GLASS
  JMP KNOCK
.dm_6:
  CMP #6
  BNE .dm_7
  LDA NLET                     ; READ LETTERS
  BNE .dm_l
  JSR MENU_CLOSE
  LDA #TX_NOLET
  JMP SPEAK
.dm_l:
  LDA #M_LET
  JMP MENU_OPEN
.dm_7:
  JSR MENU_CLOSE               ; SAVE AND QUIT
  JSR VDP_INT_ON
  JSR ST_SAVE
  JMP TITLE

; knock knock: he turns and waves, unless he is asleep or fed up
KNOCK:
  LDA #W_KNOCK
  LDX #2
  JSR SFX_WHISTLE
  LDA SLEEPING
  BEQ .kn_a
  LDA #40
  JSR ANNOY_ADD
  LDA #TX_ZZZ
  JMP SPEAK
.kn_a:
  LDA S_ANNOY
  CMP #80
  BCC .kn_ok
  LDA #20
  JSR ANNOY_ADD
  LDA #PR_EXCL
  JSR REACT
  LDA #TX_STOPKNOCK
  JMP SPEAK
.kn_ok:
  LDA #20
  JSR ANNOY_ADD
  LDX #15
  JSR JOY_ADD
  LDA #PR_HEART
  JSR REACT
  JSR NEXT_RND
  AND #3
  TAX
  LDA HELLO_TX,X
  JMP SPEAK

; A = prop: he turns to the player and waves for 2 seconds
REACT:
  STA RPROP
  LDA #120
  STA WAVET
  RTS

; X = joy to add (S_HAPPY)
JOY_ADD:
  TXA
  CLC
  ADC S_HAPPY
  BCC .ja_s
  LDA #$FF
.ja_s:
  STA S_HAPPY
  RTS

; A = annoyance to add
ANNOY_ADD:
  CLC
  ADC S_ANNOY
  BCC .an_s
  LDA #$FF
.an_s:
  STA S_ANNOY
  RTS

; ---------------------------------------------------------------
;  a gift: joy (less for the same one again, more for his favourite)
; ---------------------------------------------------------------
DO_GIFT:
  JSR MENU_CLOSE
  LDX MSEL
  STX T5
  INX
  STX S_LASTG
  LDX T5
  LDA S_GIVEN,X
  CMP #$FF
  BEQ .dg_c
  INC S_GIVEN,X
.dg_c:
  LDA S_GIVEN,X                ; joy 64, 32, 16, 8...
  CMP #5
  BCC .dg_k
  LDA #4
.dg_k:
  TAY
  LDA #128
.dg_j:
  LSR A
  DEY
  BNE .dg_j
  LDY S_PERS
  LDX T5
  PHA
  TXA
  CMP PERS_GIFT,Y
  PLA
  BNE .dg_n
  ASL A
.dg_n:
  TAX
  JSR JOY_ADD
  LDA #W_DING
  LDX #1
  JSR SFX_WHISTLE
  LDA T5                       ; what it does
  BNE .dg_1
  LDA S_BOOKS                  ; a book
  CMP #9
  BCS .dg_say
  INC S_BOOKS
  BRA .dg_say
.dg_1:
  CMP #1
  BNE .dg_2
  LDA S_RECS                   ; a record
  CMP #3
  BCS .dg_say
  INC S_RECS
  BRA .dg_say
.dg_2:
  CMP #2
  BNE .dg_3
  LDA #4                       ; flowers: 3 days, then they wilt
  STA S_FLOWER
  JSR SET_VASE
  BRA .dg_say
.dg_3:
  CMP #3
  BNE .dg_4
  LDX #N_FOOD                  ; a cake
  LDA #60
  JSR NEED_ADD
  LDX #N_FUN
  LDA #40
  JSR NEED_ADD
  BRA .dg_say
.dg_4:
  CMP #4
  BNE .dg_5
  LDX #N_HEALTH                ; tea
  LDA #60
  JSR NEED_ADD
  LDX #N_DRINK
  LDA #30
  JSR NEED_ADD
  BRA .dg_say
.dg_5:
  LDA #1                       ; a ball
  STA S_BALL
.dg_say:
  JSR MOOD_CALC
  LDA SLEEPING
  BEQ .dg_w
  LDA #TX_GIFTSLEEP
  JMP SPEAK
.dg_w:
  LDA #PR_HEART
  JSR REACT
  LDX T5
  LDA S_GIVEN,X
  CMP #4
  BCC .dg_t
  LDA #TX_AGAIN
  JMP SPEAK
.dg_t:
  LDA GIFT_TX,X
  JMP SPEAK

; ---------------------------------------------------------------
;  a request: does he do it?
; ---------------------------------------------------------------
DO_ASK:
  LDA PLEASE
  STA T6
  JSR MENU_CLOSE
  LDX MSEL
  LDA ASK_ACT,X
  STA T5                       ; the activity asked
  LDA SLEEPING                 ; asleep: only "go to bed" is all right
  BEQ .da_1
  LDA T5
  CMP #A_SLEEP
  BEQ .da_same
  LDA #30
  JSR ANNOY_ADD
  LDA #TX_ZZZ
  JMP SPEAK
.da_1:
  LDA S_ANNOY
  CMP #100
  BCC .da_2
  LDA #PR_EXCL
  JSR REACT
  LDA #TX_ALONE
  JMP SPEAK
.da_2:
  LDA #25                      ; asking annoys a little (less with "please")
  LDX T6
  BEQ .da_2a
  LDA #12
.da_2a:
  JSR ANNOY_ADD
  LDA T5                       ; already doing it
  CMP ACT
  BNE .da_3
.da_same:
  LDA #TX_DOING
  JMP SPEAK
.da_3:
  LDA NEED+N_HEALTH            ; sick: nothing tiring
  CMP #64
  BCS .da_4
  LDX T5
  LDA ACT_TIRING,X
  BEQ .da_4
  LDA #TX_TOOSICK
  JMP SPEAK
.da_4:
  LDA T5                       ; what is missing
  CMP #A_EAT
  BNE .da_4a
  LDA S_FRIDGE
  BNE .da_5
  LDA #TX_NOFOOD
  JMP SPEAK
.da_4a:
  CMP #A_DRINK
  BNE .da_4b
  LDA S_WATER
  BNE .da_5
  LDA #TX_NOWATER
  JMP SPEAK
.da_4b:
  CMP #A_BALL
  BNE .da_5
  LDA S_BALL
  BNE .da_5
  LDA #TX_NOBALL
  JMP SPEAK
.da_5:
  LDA MOOD                     ; the chance: mood / 2, + please, + if he needs it
  LSR A
  STA T7
  LDA T6
  BEQ .da_6
  LDA #80
  JSR CH_ADD
.da_6:
  LDX T5
  LDY ACT_N1,X
  LDA NEED,Y
  CMP #100
  BCS .da_7
  LDA #80
  JSR CH_ADD
  BRA .da_8
.da_7:
  CMP #220                     ; full: "I am not hungry"
  BCC .da_8
  CPX #A_EAT
  BEQ .da_full
  CPX #A_DRINK
  BEQ .da_full
  CPX #A_SLEEP
  BEQ .da_full
  CPX #A_BATH
  BNE .da_8
.da_full:
  LDA #PR_EXCL
  JSR REACT
  LDA NOTNOW_TX,X
  JMP SPEAK
.da_8:
  LDA S_ANNOY
  LSR A
  STA T4
  LDA T7
  SEC
  SBC T4
  BCS .da_9
  LDA #0
.da_9:
  STA T7
  JSR NEXT_RND
  CMP T7
  BCC .da_yes
  LDA #W_NO
  LDX #2
  JSR SFX_WHISTLE
  LDA #PR_EXCL
  JSR REACT
  JSR NEXT_RND
  AND #1
  TAX
  LDA NO_TX,X
  JMP SPEAK
.da_yes:
  LDA #W_OK
  LDX #2
  JSR SFX_WHISTLE
  LDA #TX_OK
  LDX T6
  BEQ .da_ok
  LDA #TX_PLEASURE
.da_ok:
  JSR SPEAK
  LDA T5
  JMP INTERRUPT

; A added to the chance T7 (stops at 255)
CH_ADD:
  CLC
  ADC T7
  BCC .ca_s
  LDA #$FF
.ca_s:
  STA T7
  RTS

; a letter to read
DO_LETTER:
  JSR MENU_CLOSE
  LDA MSEL                     ; 0 = the newest
  STA T0
  LDA S_LETN
  SEC
  SBC #1
  SEC
  SBC T0
  AND #3
  STA LSLOT
  JSR LETTER_SHOW
  JMP REDRAW                   ; (the VDP interrupt stays off: the frame goes on)

; A = text: Six says it on row 22 for 4 seconds
SPEAK:
  TAX
  LDA TXT_LO,X
  STA SPKP
  LDA TXT_HI,X
  STA SPKP+1
  LDA #240
  STA SPKT
  LDA #D_ROW22
  TSB DIRTY
  RTS


; ===============================================================
;  THE PANEL: row 0 and rows 20-23 (VDP interrupt off)
; ===============================================================
PANEL:
  LDA SPKT
  BEQ .pa_d
  DEC SPKT
  BNE .pa_d
  LDA #D_ROW22
  TSB DIRTY
.pa_d:
  LDA DIRTY
  BNE .pa_go
  RTS
.pa_go:
  STZ DIRTY
  PHA
  AND #D_CLOCK
  BEQ .pa_1
  JSR DRAW_CLOCK
.pa_1:
  PLA
  PHA
  AND #D_HUD
  BEQ .pa_2
  JSR DRAW_HUD
.pa_2:
  PLA
  PHA
  AND #D_BARS
  BEQ .pa_3
  JSR DRAW_BARS
.pa_3:
  PLA
  PHA
  AND #D_ROW22
  BEQ .pa_4
  JSR DRAW_R22
.pa_4:
  PLA
  AND #D_ROW23
  BEQ .pa_5
  JMP DRAW_R23
.pa_5:
  RTS

; row 0: "DAY nnnn  hh:mm"
DRAW_CLOCK:
  LDX #0
  LDY #0
  JSR NT_XY
  LDA #<TXT_DAYH
  LDY #>TXT_DAYH
  JSR PUTS
  LDA S_DAY
  STA NUM16
  LDA S_DAY+1
  STA NUM16+1
  JSR PUT_NUM16
  LDA #$20                     ; the rest of the 4 digits (a loop keeps the writes 8+ cycles apart)
  LDX #3
.dc_sp:
  STA VDATA
  DEX
  BNE .dc_sp
  LDX #0
  LDY #9
  JSR NT_XY
  LDA S_HOUR
  JSR BIN2BCD
  JSR PUT_2
  LDA #':'
  STA VDATA
  LDA S_MIN
  JSR BIN2BCD
  JMP PUT_2

; row 0: the face and the mood, fridge, water, bowl, mail
DRAW_HUD:
  LDX #0
  LDY #15
  JSR NT_XY
  LDX FACEI
  LDA FACE_T,X
  STA VDATA
  LDA MOOD_LO,X
  LDY MOOD_HI,X
  JSR PUTS
  LDX #0
  LDY #22
  JSR NT_XY
  LDA #T_FOOD
  STA VDATA
  LDA S_FRIDGE
  ORA #$30
  STA VDATA
  LDA #$20
  STA VDATA
  LDA #T_WATER
  STA VDATA
  LDA S_WATER
  ORA #$30
  STA VDATA
  LDA #$20
  STA VDATA
  LDA #T_CAT
  STA VDATA
  LDA S_BOWL
  ORA #$30
  STA VDATA
  LDA #$20
  STA VDATA
  STA VDATA
  LDA #$20
  LDX S_UNREAD
  BEQ .dh_m
  LDA #T_MAIL
.dh_m:
  STA VDATA
  RTS

; rows 20-21: six bars of 4 tiles
DRAW_BARS:
  LDX #5
.db_l:
  PHX
  LDA BAR_R,X
  LDY BAR_C,X
  TAX
  JSR NT_XY
  PLX
  LDA NEED,X
  CMP #64
  LDY #0                       ; Y = 0 green, 9 red
  BCS .db_g
  LDY #9
.db_g:
  STY T3
  LSR A
  LSR A
  LSR A
  STA T2                       ; 0-31
  LDY #4
.db_t:
  LDA T2
  CMP #8
  BCC .db_p
  LDA #8
.db_p:
  STA T1
  CLC
  ADC T3
  PHX
  TAX
  LDA BAR_T,X
  STA VDATA
  PLX
  LDA T2
  SEC
  SBC T1
  STA T2
  DEY
  BNE .db_t
  DEX
  BPL .db_l
  RTS

; row 22: the menu title or the words of Six
DRAW_R22:
  STZ T5
  LDX #22
  LDY #0
  JSR NT_XY
  LDA MENU
  BEQ .d2_s
  TAX
  LDA MTITLE_LO-1,X
  LDY MTITLE_HI-1,X
  CPX #M_ASK
  BNE .d2_p
  LDX PLEASE
  BEQ .d2_p
  LDA #<TXT_MPLEASE
  LDY #>TXT_MPLEASE
.d2_p:
  JSR PUTS
  BRA .d2_pad
.d2_s:
  LDA SPKT
  BEQ .d2_pad
  LDA SPKP
  LDY SPKP+1
  JSR PUTS
.d2_pad:
  JMP PAD_ROW

; row 23: the item of the menu, or the hint
DRAW_R23:
  STZ T5
  LDX #23
  LDY #0
  JSR NT_XY
  LDA MENU
  BNE .d3_m
  LDA #<TXT_HINT
  LDY #>TXT_HINT
  JSR PUTS
  JMP PAD_ROW
.d3_m:
  CMP #M_LET                   ; a letter: "LETTER OF DAY n"
  BNE .d3_t
  LDA #<TXT_ARROWL
  LDY #>TXT_ARROWL
  JSR PUTS
  LDA #<TXT_LETOF
  LDY #>TXT_LETOF
  JSR PUTS
  LDA S_LETN
  SEC
  SBC #1
  SEC
  SBC MSEL
  AND #3
  ASL A
  ASL A
  ASL A
  TAX
  LDA S_LETS,X
  STA NUM16
  LDA S_LETS+1,X
  STA NUM16+1
  JSR PUT_NUM16
  BRA .d3_r
.d3_t:
  TAX                          ; the list of the menu
  LDA MLIST_LO-1,X
  STA PTR2
  LDA MLIST_HI-1,X
  STA PTR2+1
  LDA MSEL
  ASL A
  TAY
  LDA (PTR2),Y
  PHA
  INY
  LDA (PTR2),Y
  PHA
  LDA #<TXT_ARROWL
  LDY #>TXT_ARROWL
  JSR PUTS
  PLY
  PLA
  JSR PUTS
.d3_r:
  LDA #<TXT_ARROWR
  LDY #>TXT_ARROWR
  JSR PUTS
  ; fall into PAD_ROW

; spaces to the end of the row (T5 = characters written by PUTS on the row)
PAD_ROW:
  LDA T5
.pr_l:
  CMP #32
  BCS .pr_e
  LDX #$20
  STX VDATA
  INC A
  BRA .pr_l
.pr_e:
  STZ T5
  RTS

; A / Y = string (0 at the end): where the VDP points; T5 counts the characters
PUTS:
  STA PTR
  STY PTR+1
  LDY #0
.pu_l:
  LDA (PTR),Y
  BEQ .pu_e
  STA VDATA
  INC T5
  INY
  BNE .pu_l
.pu_e:
  RTS

; NUM16 (0-9999) without leading zeros, where the VDP points
PUT_NUM16:
  LDX #0                       ; thousands, hundreds, tens by subtraction
  STZ T4                       ; 1 = a digit was written
.pn_d:
  LDY #0
.pn_s:
  LDA NUM16
  SEC
  SBC DEC_LO,X
  STA T6
  LDA NUM16+1
  SBC DEC_HI,X
  BCC .pn_w
  STA NUM16+1
  LDA T6
  STA NUM16
  INY
  BRA .pn_s
.pn_w:
  TYA
  BNE .pn_o
  LDA T4
  BEQ .pn_n
  TYA
.pn_o:
  ORA #$30
  STA VDATA
  INC T5
  LDA #1
  STA T4
.pn_n:
  INX
  CPX #3
  BNE .pn_d
  LDA NUM16
  ORA #$30
  STA VDATA
  INC T5
  RTS


; ===============================================================
;  THE HOUSE ON THE SCREEN (VDP interrupt off)
; ===============================================================
REDRAW:
  LDA #$82                     ; display off while it is drawn
  STA VREG
  LDA #(VDP_REGISTER_BITS | 1)
  STA VREG
  JSR CLEAR_NT
  LDA #<HOUSE_NT
  STA PTR
  LDA #>HOUSE_NT
  STA PTR+1
  LDA #$20
  STA T0
  LDA #(VDP_WRITE_VRAM_BIT | $38)
  STA T1
  LDA #<608
  STA T2
  LDA #>608
  STA T3
  JSR VCOPY
  JSR SET_WINDOWS
  JSR SET_VASE
  JSR SET_BOWL
  JSR SET_MAIL
  LDA OBJA                     ; the object of what he is doing
  BMI .rd_l
  TAX
  LDA #1
  JSR OBJ_SET
.rd_l:
  LDA #<TXT_LABELS
  STA TP
  LDA #>TXT_LABELS
  STA TP+1
  JSR PRINT
  JSR LET_COUNT
  LDA #$FF
  STA DIRTY
  STZ T5
  JSR PANEL
  LDA #$C6                     ; display on (interrupt still off)
  STA VREG
  LDA #(VDP_REGISTER_BITS | 1)
  STA VREG
  RTS

; X = object, A = state: its tiles on the screen
OBJ_SET:
  STX T5
  STA T4
  LDA OBJ_TLO,X
  STA PTR
  LDA OBJ_THI,X
  STA PTR+1
.os_m:                         ; + state x tiles of a state
  LDA T4
  BEQ .os_d
  LDA PTR
  CLC
  ADC OBJ_N,X
  STA PTR
  BCC .os_m1
  INC PTR+1
.os_m1:
  DEC T4
  BRA .os_m
.os_d:
  LDA OBJ_ROW,X
  STA T2
  LDA OBJ_H,X
  STA T3
  LDY #0
.os_r:
  PHY
  LDX T2
  LDY T5
  LDA OBJ_COL,Y
  TAY
  JSR NT_XY
  PLY
  LDX T5
  LDA OBJ_W,X
  TAX
.os_c:
  LDA (PTR),Y
  STA VDATA
  INY
  DEX
  BNE .os_c
  INC T2
  DEC T3
  BNE .os_r
  LDX T5
  STZ T5
  RTS

; the objects in time: the activity (two frames), the alarm clock
OBJ_ANIM:
  LDA ALARMT
  BEQ .oa_a
  DEC ALARMT
  BEQ .oa_off
  LDA ALARMT
  AND #3
  BNE .oa_a
  LDA ALARMT
  AND #4
  LSR A
  LSR A
  INC A
  LDX #O_CLOCK
  JMP OBJ_SET
.oa_off:
  LDX #O_CLOCK
  LDA #0
  JMP OBJ_SET
.oa_a:
  LDA OBJA
  BMI .oa_e
  LDA APH
  CMP #1
  BNE .oa_e
  LDX OBJA
  LDA OBJ_S,X
  CMP #3
  BCC .oa_e
  DEC ANIMT
  BPL .oa_e
  LDA #12
  STA ANIMT
  LDA OBJST
  EOR #3
  AND #3
  BNE .oa_s
  LDA #1
.oa_s:
  STA OBJST
  JMP OBJ_SET
.oa_e:
  RTS

SET_WINDOWS:
  JSR IS_DARK
  LDA #0
  ROL A
  LDX #O_WIN1
.sw_l:
  PHA
  JSR OBJ_SET
  PLA
  INX
  CPX #O_WIN4+1
  BNE .sw_l
  RTS

; C = 1 from 20:00 to 5:59
IS_DARK:
  LDA S_HOUR
  CMP #20
  BCS .id_e
  CMP #6
  BCC .id_y
  CLC
  RTS
.id_y:
  SEC
.id_e:
  RTS

SET_VASE:
  LDA S_FLOWER
  BEQ .sv_s
  CMP #1
  BEQ .sv_w
  LDA #1
  BRA .sv_s
.sv_w:
  LDA #2
.sv_s:
  LDX #O_VASE
  JMP OBJ_SET

SET_BOWL:
  LDA S_BOWL
  BEQ .sb_s
  LDA #1
.sb_s:
  LDX #O_BOWL
  JMP OBJ_SET

SET_MAIL:
  LDA S_UNREAD
  LDX #O_MAIL
  JMP OBJ_SET


; ===============================================================
;  SPRITES: Six (overalls and skin), Byte, a prop
; ===============================================================
BUILD_SAT:
  JSR SIX_POSE
  JSR SAT_SIXD
  JSR SAT_CAT
  JSR PROP_SET
  LDA PROPN
  BEQ .bs_e
  STA ON
  LDA PROPX
  STA OX
  LDA PROPY
  STA OY
  LDA PROPC
  STA OC
  JSR ADD_SPR
.bs_e:
  JMP SAT_END

; A = pose of Six now, T4 = its height change
SIX_POSE:
  STZ T4
  LDA TOURI                    ; a stop of the visit: its pose
  BEQ .xp_0
  LDA WAVET
  BEQ .xp_0
  LDA TPOSE
  BPL .xp_w
.xp_0:
  LDA WAVET
  BEQ .xp_1
  LDA #PO_WAVE1
  BIT FRAME_CNT
  BVC .xp_w
  LDA #PO_WAVE2
.xp_w:
  RTS
.xp_1:
  LDA APH
  BNE .xp_2
  LDA CLIMBF
  BEQ .xp_wk
  LDA SIXY
  LSR A
  LSR A
  LSR A
  AND #1
  CLC
  ADC #PO_CLIMB1
  RTS
.xp_wk:
  LDA WALKC
  LSR A
  LSR A
  LSR A
  AND #1
  LDX FACE
  BEQ .xp_r
  CLC
  ADC #PO_WALKL1
  RTS
.xp_r:
  CLC
  ADC #PO_WALKR1
  RTS
.xp_2:
  CMP #1
  BNE .xp_f
  LDY ACT
  LDA ACT_DY,Y
  STA T4
  LDA ACT_ANIM,Y
  BEQ .xp_s
  LDA FRAME_CNT
  LSR A
  LSR A
  LSR A
  LSR A
  AND #1
.xp_s:
  CLC
  ADC ACT_POSE,Y
  RTS
.xp_f:
  LDA #PO_FRONT
  RTS

; A = pose: the two sprites of Six at SIXX / SIXY (+ T4); the list starts again
SAT_SIX:
  STZ T4
SAT_SIXD:
  STZ SPRN
  ASL A
  ASL A
  ASL A
  STA ON
  LDA SIXX
  STA OX
  LDA SIXY
  CLC
  ADC T4
  STA OY
  LDA #C_SUIT
  STA OC
  JSR ADD_SPR
  LDA ON
  CLC
  ADC #4
  STA ON
  LDA #C_SKIN
  STA OC
  JMP ADD_SPR

SAT_CAT:
  LDA CATP
  ASL A
  ASL A
  STA ON
  LDA CATX
  STA OX
  LDA CATY
  STA OY
  LDA #C_CAT
  STA OC
  JMP ADD_SPR

; the prop of the reaction or of the activity
PROP_SET:
  STZ PROPN
  LDA WAVET
  BEQ .ps_a
  LDA RPROP
  BEQ .ps_e
  BRA .ps_p
.ps_a:
  LDA APH
  CMP #1
  BNE .ps_e
  LDY ACT
  LDA ACT_PROP,Y
  BEQ .ps_e
.ps_p:
  STA T6
  SEC
  SBC #PR_Z1
  TAX
  LDA PROP_AN,X                ; two frames
  BEQ .ps_1
  LDA FRAME_CNT
  AND #32
  BEQ .ps_1
  LDA #1
.ps_1:
  CLC
  ADC T6
  ASL A
  ASL A
  STA PROPN
  LDA SIXX
  CLC
  ADC PROP_DX,X
  STA PROPX
  LDA SIXY
  CLC
  ADC PROP_DY,X
  STA PROPY
  LDA PROP_CO,X
  STA PROPC
  CPX #(PR_BALL-PR_Z1)         ; the ball bounces
  BNE .ps_e
  LDA FRAME_CNT
  LSR A
  AND #15
  TAY
  LDA PROPY
  SEC
  SBC BOUNCE,Y
  STA PROPY
.ps_e:
  RTS

; OX, OY, ON, OC: one sprite more in the list
ADD_SPR:
  LDX SPRN
  LDA OY
  DEC A
  STA SAT_BUFFER,X
  LDA OX
  STA SAT_BUFFER+1,X
  LDA ON
  STA SAT_BUFFER+2,X
  LDA OC
  STA SAT_BUFFER+3,X
  TXA
  CLC
  ADC #4
  STA SPRN
  RTS

SAT_END:
  LDX SPRN
  LDA #$D0
  STA SAT_BUFFER,X
  INX
  STX SATB
  RTS

; ===============================================================
;  HI-LO BITS: a number on 8 lights, will the next one be higher
;  or lower? Ten rounds, the player against Six.
;  Called with the VDP interrupt on; returns with it on.
; ===============================================================
HLI         = $96      ; the light being revealed
LROW        = $97      ; the row of the letter being written

HILO:
  LDA #CMD_GAME
  STA SND_CMD
  JSR VDP_INT_OFF
  JSR CLEAR_NT
  LDA #<TXT_HL
  STA TP
  LDA #>TXT_HL
  STA TP+1
  JSR PRINT
  LDA #PO_SITR1                ; Six at his computer, on the right
  JSR HL_SIX
  JSR VDP_INT_ON
  STZ HLYOU
  STZ HLSIX
  LDA #1
  STA HLR
  JSR HL_RAND
  STA HLN
.hl_round:
  JSR VDP_INT_OFF
  LDA HLN
  JSR HL_LIGHTS
  JSR HL_SCORE
  LDA #<TXT_HLASK
  STA TP
  LDA #>TXT_HLASK
  STA TP+1
  JSR PRINT
  LDA #PO_FRONT
  JSR HL_SIX
  JSR VDP_INT_ON
.hl_in:                        ; UP higher, DOWN lower, button 2 stops
  JSR WAIT_FRAME
  JSR READ_JOY
  JSR JOY_EDGE
  LDA JNEW
  BIT #J_B2
  BEQ .hl_i1
  JMP .hl_quit
.hl_i1:
  LDX #1
  BIT #J_UP
  BNE .hl_g
  LDX #0
  BIT #J_DOWN
  BEQ .hl_in
.hl_g:
  STX HLG
  LDA #W_MENU
  LDX #0
  JSR SFX_WHISTLE
  ; ---- Six guesses: the likely way, sometimes not
  LDX #1
  LDA HLN
  BPL .hl_s1
  LDX #0
.hl_s1:
  LDA HLN                      ; near the middle he tosses a coin
  SEC
  SBC #104
  CMP #48
  BCS .hl_s2
  JSR NEXT_RND
  CMP #AI_HILO_LUCK+88
  BCS .hl_s2
  JSR NEXT_RND
  AND #1
  TAX
  BRA .hl_s3
.hl_s2:
  JSR NEXT_RND
  CMP #AI_HILO_ERR
  BCS .hl_s3
  TXA
  EOR #1
  TAX
.hl_s3:
  STX HLS
  JSR VDP_INT_OFF
  LDA #<TXT_HLWAIT
  STA TP
  LDA #>TXT_HLWAIT
  STA TP+1
  JSR PRINT
  LDX #15
  LDY #4
  JSR NT_XY
  LDA #<TXT_HLYOU
  LDY #>TXT_HLYOU
  JSR PUTS
  LDX HLG
  JSR HL_WAY
  LDX #16
  LDY #4
  JSR NT_XY
  LDA #<TXT_HLSIXS
  LDY #>TXT_HLSIXS
  JSR PUTS
  LDX HLS
  JSR HL_WAY
  JSR VDP_INT_ON
  LDA #40
  JSR WAIT_FRAMES
  ; ---- the next number, one light after the other
  JSR HL_RAND
  STA HLM
  STZ HLI
.hl_b:
  JSR VDP_INT_OFF
  LDX HLI                      ; lights 0..HLI of the new number, the others off
  LDA #$FF
.hl_m:
  LSR A
  DEX
  BPL .hl_m
  EOR #$FF                     ; the HLI+1 top bits
  AND HLM
  JSR HL_LIGHTS
  JSR VDP_INT_ON
  LDX HLI
  LDA HLM
.hl_bit:
  ASL A
  DEX
  BPL .hl_bit
  LDA #W_BIT0
  BCC .hl_bs
  LDA #W_BIT1
.hl_bs:
  LDX #2
  JSR SFX_WHISTLE
  LDA #8
  JSR WAIT_FRAMES
  INC HLI
  LDA HLI
  CMP #8
  BNE .hl_b
  ; ---- who was right
  JSR VDP_INT_OFF
  LDA HLM
  JSR HL_LIGHTS
  LDA HLM
  CMP HLN
  BNE .hl_r1
  LDA #<TXT_HLSAME
  LDY #>TXT_HLSAME
  BRA .hl_msg
.hl_r1:
  LDA #0                       ; T6 = 1 if it went up
  ROL A
  STA T6
  STZ T5
  LDA HLG
  CMP T6
  BNE .hl_r2
  INC HLYOU
  LDA #1
  STA T5
.hl_r2:
  LDA HLS
  CMP T6
  BNE .hl_r3
  INC HLSIX
  LDA T5
  ORA #2
  STA T5
.hl_r3:
  LDX T5
  LDA HLRES_LO,X
  LDY HLRES_HI,X
.hl_msg:
  PHA
  PHY
  LDX #18
  LDY #0
  JSR NT_XY
  STZ T5
  PLY
  PLA
  JSR PUTS
  JSR PAD_ROW
  JSR HL_SCORE
  JSR VDP_INT_ON
  LDA #W_OK
  LDX #2
  JSR SFX_WHISTLE
  LDA #100
  JSR WAIT_FRAMES
  LDA HLM
  STA HLN
  INC HLR
  LDA HLR
  CMP #11
  BCS .hl_end
  JMP .hl_round
  ; ---- the end: who won
.hl_end:
  JSR VDP_INT_OFF
  LDX #18
  LDY #0
  JSR NT_XY
  STZ T5
  LDA HLYOU
  CMP HLSIX
  BEQ .hl_draw
  BCC .hl_six
  LDA #2                       ; the player
  STA S_HILO
  LDA #<TXT_HLWIN
  LDY #>TXT_HLWIN
  JSR PUTS
  LDA #W_WIN
  LDX #PO_SAD
  BRA .hl_fin
.hl_six:
  LDA #1
  STA S_HILO
  LDA #<TXT_HLLOSE
  LDY #>TXT_HLLOSE
  JSR PUTS
  LDA #W_HAPPY
  LDX #PO_WAVE1
  BRA .hl_fin
.hl_draw:
  LDA #<TXT_HLDRAW
  LDY #>TXT_HLDRAW
  JSR PUTS
  LDA #W_OK
  LDX #PO_FRONT
.hl_fin:
  PHA
  PHX
  JSR PAD_ROW
  LDA #<TXT_HLBACK
  STA TP
  LDA #>TXT_HLBACK
  STA TP+1
  JSR PRINT
  PLA
  JSR HL_SIX
  JSR VDP_INT_ON
  PLA
  LDX #2
  JSR SFX_WHISTLE
  LDA HLYOU                    ; the best of the player
  CMP S_BEST
  BCC .hl_b2
  STA S_BEST
.hl_b2:
  LDX #N_FUN                   ; Six had fun, more if he won
  LDA #80
  LDY S_HILO
  CPY #1
  BNE .hl_f
  LDA #110
.hl_f:
  JSR NEED_ADD
  LDX #40
  JSR JOY_ADD
  JSR MOOD_CALC
.hl_w:                         ; a button: back to the house
  JSR WAIT_FRAME
  JSR READ_JOY
  JSR JOY_EDGE
  LDA JNEW
  AND #BTN_MASK
  BEQ .hl_w
  RTS
.hl_quit:
  LDX #N_FUN
  LDA #20
  JMP NEED_ADD

; a number 0-255
HL_RAND:
  JSR NEXT_RND
  EOR FRAME_CNT
  RTS

; X = 1 "HIGHER", 0 "LOWER" where the VDP points
HL_WAY:
  LDA HLWAY_LO,X
  LDY HLWAY_HI,X
  JMP PUTS

; A = number: the 8 lights (row 9), its bits (row 11), its value (row 13)
HL_LIGHTS:
  STA T4
  LDX #9
  LDY #8
  JSR NT_XY
  LDA T4
  STA T3
  LDX #8
.hli_l:
  ASL T3
  LDA #T_LEDOFF
  BCC .hli_o
  LDA #T_LEDON
.hli_o:
  STA VDATA
  LDA #$20
  STA VDATA
  DEX
  BNE .hli_l
  LDX #11
  LDY #8
  JSR NT_XY
  LDA T4
  STA T3
  LDX #8
.hli_b:
  ASL T3
  LDA #'0'
  BCC .hli_z
  LDA #'1'
.hli_z:
  STA VDATA
  LDA #$20
  STA VDATA
  DEX
  BNE .hli_b
  LDX #13
  LDY #13
  JSR NT_XY
  LDA #'='
  STA VDATA
  LDA #' '
  STA VDATA
  LDA T4
  STA NUM16
  STZ NUM16+1
  JSR PUT_NUM16
  LDA #' '
  STA VDATA
  STA VDATA
  RTS

; row 4: YOU n  SIX n  ROUND n/10
HL_SCORE:
  LDX #4
  LDY #3
  JSR NT_XY
  LDA #<TXT_HLSC1
  LDY #>TXT_HLSC1
  JSR PUTS
  LDA HLYOU
  JSR HL_N2
  LDA #<TXT_HLSC2
  LDY #>TXT_HLSC2
  JSR PUTS
  LDA HLSIX
  JSR HL_N2
  LDA #<TXT_HLSC3
  LDY #>TXT_HLSC3
  JSR PUTS
  LDA HLR
  CMP #11
  BCC .hs_r
  LDA #10
.hs_r:
  STA NUM16
  STZ NUM16+1
  JSR PUT_NUM16
  LDA #<TXT_HOF10
  LDY #>TXT_HOF10
  JMP PUTS

; A = 0-10: two characters
HL_N2:
  CMP #10
  BCC .hn_1
  LDX #'1'
  STX VDATA
  LDA #'0'
  STA VDATA
  RTS
.hn_1:
  ORA #$30
  STA VDATA
  LDA #' '
  STA VDATA
  RTS

; A = pose: Six alone on the screen of the game (VDP interrupt off)
HL_SIX:
  LDX SIXX
  PHX
  LDX SIXY
  PHX
  LDX #208
  STX SIXX
  LDX #96
  STX SIXY
  JSR SAT_SIX
  JSR SAT_END
  PLA
  STA SIXY
  PLA
  STA SIXX
  RTS


; ===============================================================
;  LETTERS: 4 kept (8 bytes each), composed when they are read
; ===============================================================
LETTER_NEW:
  LDA S_LETN
  AND #3
  ASL A
  ASL A
  ASL A
  TAX
  LDA S_DAY
  STA S_LETS,X
  STA S_LETD
  LDA S_DAY+1
  STA S_LETS+1,X
  LDA FACEI
  STA S_LETS+2,X
  LDA S_LASTG
  STA S_LETS+3,X
  STZ S_LASTG
  LDA S_HILO
  STA S_LETS+5,X
  STZ S_HILO
  JSR NEXT_RND
  STA S_LETS+6,X
  LDA #0
  LDY S_CATF
  CPY #100
  ROL A
  STA S_LETS+7,X
  LDY #7                       ; what he wants: the lowest need, Byte's food, nothing
  LDA #100
  STA T0
  PHX
  LDX #5
.ln_w:
  LDA NEED,X
  CMP T0
  BCS .ln_n
  STA T0
  TXA
  TAY
.ln_n:
  DEX
  BPL .ln_w
  PLX
  CPY #7
  BNE .ln_s
  LDA S_CATF
  CMP #80
  BCS .ln_s
  LDY #6
.ln_s:
  TYA
  STA S_LETS+4,X
  INC S_LETN
  BNE .ln_c
  LDA #251                     ; (stays a multiple of 4 plus 3, at least 4 letters)
  STA S_LETN
.ln_c:
  LDA #1
  STA S_UNREAD
  JSR SET_MAIL
  LDA #D_HUD
  TSB DIRTY
  ; fall into LET_COUNT

; NLET = letters that can be read (at most 4)
LET_COUNT:
  LDA S_LETN
  CMP #4
  BCC .lc_s
  LDA #4
.lc_s:
  STA NLET
  RTS

; the letter LSLOT on paper (VDP interrupt off; returns with it off)
LETTER_SHOW:
  STZ S_UNREAD
  JSR HIDE_SPRITES
  LDA #$1B                     ; the font black on light yellow
  JSR FONT_COL
  JSR CLEAR_NT
  LDA LSLOT
  ASL A
  ASL A
  ASL A
  TAX
  STX LSLOT
  LDA S_LETS+6,X
  STA LSEED
  LDA #1
  STA LROW                       ; the row
  LDA #<TXT_LFROM
  LDY #>TXT_LFROM
  JSR L_LINE
  INC LROW
  LDA LSEED                    ; "DEAR FRIEND,"
  AND #3
  TAX
  LDA GREET_LO,X
  LDY GREET_HI,X
  JSR L_LINE
  INC LROW
  JSR L_ROW                    ; "IT IS DAY n IN MY HOUSE."
  LDA #<TXT_LDAY1
  LDY #>TXT_LDAY1
  JSR PUTS
  LDX LSLOT
  LDA S_LETS,X
  STA NUM16
  LDA S_LETS+1,X
  STA NUM16+1
  JSR PUT_NUM16
  LDA #<TXT_LDAY2
  LDY #>TXT_LDAY2
  JSR PUTS
  INC LROW
  LDX LSLOT                    ; his mood
  LDA S_LETS+2,X
  ASL A
  STA T0
  LDA LSEED
  LSR A
  LSR A
  AND #1
  ORA T0
  TAX
  LDA MOODL_LO,X
  LDY MOODL_HI,X
  JSR L_LINE
  LDX S_PERS                   ; his character
  LDA PERSL_LO,X
  LDY PERSL_HI,X
  JSR L_LINE
  LDX LSLOT                    ; Byte
  LDA S_LETS+7,X
  BEQ .ls_ch
  LDA LSEED
  LSR A
  LSR A
  LSR A
  AND #1
  TAX
  LDA CATL_LO,X
  LDY CATL_HI,X
  BRA .ls_c
.ls_ch:
  LDA #<TXT_LCATH
  LDY #>TXT_LCATH
.ls_c:
  JSR L_LINE
  LDX LSLOT                    ; the gift
  LDA S_LETS+3,X
  BEQ .ls_ng
  DEC A
  PHA
  JSR L_ROW
  LDA #<TXT_LTHANK
  LDY #>TXT_LTHANK
  JSR PUTS
  PLX
  LDA GIFTN_LO,X
  LDY GIFTN_HI,X
  JSR PUTS
  LDA #'!'
  STA VDATA
  INC LROW
  BRA .ls_w
.ls_ng:
  LDA S_LETS+2,X
  CMP #2
  BCC .ls_w
  LDA #<TXT_LNOGIFT
  LDY #>TXT_LNOGIFT
  JSR L_LINE
.ls_w:
  LDX LSLOT                    ; what he wants
  LDA S_LETS+4,X
  TAX
  LDA WANTL_LO,X
  LDY WANTL_HI,X
  JSR L_LINE
  LDX LSLOT                    ; HI-LO BITS
  LDA S_LETS+5,X
  BEQ .ls_b
  TAX
  LDA HILOL_LO-1,X
  LDY HILOL_HI-1,X
  JSR L_LINE
.ls_b:
  INC LROW
  INC LROW
  LDA LSEED
  LSR A
  LSR A
  LSR A
  LSR A
  AND #3
  TAX
  LDA BYE_LO,X
  LDY BYE_HI,X
  JSR L_LINE
  LDA #<TXT_LSIX
  LDY #>TXT_LSIX
  JSR L_LINE
  LDA #<TXT_LBACK
  STA TP
  LDA #>TXT_LBACK
  STA TP+1
  JSR PRINT
  LDA #W_PAGE
  LDX #2
  JSR SFX_WHISTLE
  JSR VDP_INT_ON
.lw_r:                         ; buttons released, then a button
  JSR WAIT_FRAME
  JSR READ_JOY
  JSR JOY_EDGE
  LDA JOYC
  AND #BTN_MASK
  BNE .lw_r
.lw_p:
  JSR WAIT_FRAME
  JSR READ_JOY
  JSR JOY_EDGE
  LDA JNEW
  AND #BTN_MASK
  BEQ .lw_p
  JSR VDP_INT_OFF
  LDA #$F1                     ; the font white on black again
  JMP FONT_COL

; A / Y = text: on row LROW from column 2, then the next row
L_LINE:
  PHA
  PHY
  JSR L_ROW
  PLY
  PLA
  JSR PUTS
  INC LROW
  RTS

L_ROW:
  LDX LROW
  LDY #2
  JMP NT_XY

; A = colour of the font tiles (32-95) in the three thirds
FONT_COL:
  STA T5
  LDX #0
.fc_l:
  STZ T0
  LDA FC_HI,X
  STA T1
  STZ T2
  LDA #2
  STA T3
  LDA T5
  PHX
  JSR VFILL
  PLX
  INX
  CPX #3
  BNE .fc_l
  RTS
FC_HI:      .byte $61,$69,$71   ; colours of tile 32 in the three thirds (+ write bit)


; ===============================================================
;  SCREEN: VRAM, texts, sprites, sound (from robo vac)
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
  LDA #4                        ; the records (songs 1-4): the piano
  LDX SONG
  BEQ .ss_o
  CPX #5
  BCC .ss_p
.ss_o:
  LDA #0
.ss_p:
  STA ENVO
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
  TXA
  ORA ENVO
  TAY
  LDA V0_TAB,Y
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
  TXA
  ORA ENVO
  TAY
  INC TR_AGE,X
  LDA TR_AGE,X
  AND DECMASK_TAB,Y
  BNE .mt_next
  LDA TR_VOL,X
  CMP FLOOR_TAB,Y
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
BITS:       .byte 1,2,4,8,16,32,64,128
FLOOR_Y:    .byte 40,80,120                    ; top of Six standing on the attic, first and ground floor
DEC_LO:     .byte <1000,<100,<10
DEC_HI:     .byte >1000,>100,>10

; ---------------- the activities ----------------
A_SLEEP     = 0
A_EAT       = 1
A_DRINK     = 2
A_BATH      = 3
A_READ      = 4
A_MUSIC     = 5
A_EXER      = 6
A_PC        = 7
A_HILO      = 8
A_LETTER    = 9
A_TINKER    = 10
A_BALL      = 11
A_IDLE      = 12
A_COMPLAIN  = 13
;              sleep    eat      drink    bath     read     music    exer     pc       hilo     letter   tinker   ball     idle     complain
ACT_F:      .byte 0,       2,       2,       1,       2,       2,       0,       1,       1,       1,       0,       0,       0,       2
ACT_X:      .byte 90,      92,      64,      72,      152,     172,     204,     144,     144,     184,     160,     184,     0,       64
ACT_POSE:   .byte PO_LIE,  PO_SITR1,PO_DRINK,PO_BATH1,PO_READ, PO_DANCE1,PO_BIKE1,PO_SITR1,PO_SITR1,PO_SITR1,PO_HAMMER1,PO_FRONT,PO_FRONT,PO_SAD
ACT_ANIM:   .byte 0,       1,       0,       1,       0,       1,       1,       1,       1,       1,       1,       0,       0,       0
ACT_DY:     .byte 0,       0,       0,       $F4,     0,       0,       0,       0,       0,       0,       0,       0,       0,       0
ACT_MIN:    .byte 1,       20,      5,       25,      45,      30,      30,      45,      1,       20,      40,      20,      15,      15
ACT_N1:     .byte N_REST,  N_FOOD,  N_DRINK, N_CLEAN, N_FUN,   N_FUN,   N_FUN,   N_FUN,   N_FUN,   N_FUN,   N_FUN,   N_FUN,   N_FUN,   N_FUN
ACT_D1:     .byte 2,       9,       40,      10,      2,       4,       2,       3,       0,       2,       2,       5,       0,       $FF
ACT_N2:     .byte $FF,     N_FUN,   $FF,     N_FUN,   N_REST,  N_REST,  N_HEALTH,$FF,     $FF,     $FF,     N_CLEAN, N_CLEAN, $FF,     $FF
ACT_D2:     .byte 0,       1,       0,       1,       1,       $FF,     1,       0,       0,       0,       $FF,     $FF,     0,       0
ACT_OBJ:    .byte $FF,     O_STOVE, $FF,     O_BATH,  $FF,     O_REC,   $FF,     O_PC,    O_PC,    O_TYPE,  $FF,     $FF,     $FF,     $FF
ACT_SND:    .byte W_SNORE, S_SIZZLE|$80,0,   S_SPLASH|$80,W_PAGE,0,     S_PEDAL|$80,W_BEEP,0,     W_TYPE,  S_TOK|$80,W_BOUNCE,0,     W_SIGH
ACT_SNDP:   .byte 100,     50,      60,      40,      230,     60,      24,      30,      60,      6,       30,      32,      60,      150
ACT_PROP:   .byte PR_Z1,   0,       0,       PR_BUB1, 0,       PR_NOTE1,0,       0,       0,       0,       0,       PR_BALL, 0,       0
ACT_TIRING: .byte 0,       0,       0,       0,       0,       1,       1,       0,       0,       0,       1,       1,       0,       0
NOTNOW_TX:  .byte TX_NOTTIRED,TX_NOTHUNGRY,TX_NOTTHIRSTY,TX_CLEAN,TX_OK,TX_OK,TX_OK,TX_OK,TX_OK,TX_OK,TX_OK,TX_OK,TX_OK,TX_OK
; the places where he just stands about: floor, x
IDLE_F:     .byte 0,0,1,1,2,2,0,1
IDLE_X:     .byte 60,176,104,168,116,200,132,40
; what can be asked (the ASK menu)
ASK_ACT:    .byte A_EAT,A_DRINK,A_SLEEP,A_BATH,A_READ,A_MUSIC,A_EXER,A_PC,A_HILO,A_LETTER,A_TINKER,A_BALL

; ---------------- the needs ----------------
DECAY_P:    .byte 3,2,4,4,2                    ; minutes for every drop: food, drink, rest, clean, fun
LOW_TX:     .byte TX_HUNGRY,TX_THIRSTY,TX_TIRED,TX_DIRTY,TX_BORED,TX_UNWELL
BAR_R:      .byte 20,20,20,21,21,21
BAR_C:      .byte 6,16,28,6,16,28

; ---------------- his character: tidy, lazy, musical, sporty, bookish, foodie ----------------
PERS_NEED:  .byte N_CLEAN,N_REST,N_FUN,N_DRINK,N_FUN,N_FOOD
PERS_FAV:   .byte A_TINKER,A_READ,A_MUSIC,A_EXER,A_READ,A_PC
PERS_GIFT:  .byte 2,4,1,5,0,3                  ; flowers, tea, record, ball, book, cake
WAKE_H:     .byte 7,9,7,6,7,7
BED_H:      .byte 23,23,23,22,23,23
FREE_T:
  .byte A_TINKER,A_TINKER,A_READ,A_PC,A_EXER,A_MUSIC,A_IDLE,A_IDLE
  .byte A_READ,A_READ,A_IDLE,A_IDLE,A_PC,A_MUSIC,A_READ,A_IDLE
  .byte A_MUSIC,A_MUSIC,A_MUSIC,A_READ,A_PC,A_IDLE,A_TINKER,A_EXER
  .byte A_EXER,A_EXER,A_BALL,A_BALL,A_IDLE,A_MUSIC,A_PC,A_READ
  .byte A_READ,A_READ,A_READ,A_PC,A_PC,A_IDLE,A_MUSIC,A_TINKER
  .byte A_PC,A_PC,A_READ,A_MUSIC,A_IDLE,A_IDLE,A_TINKER,A_EXER

; ---------------- a new house ----------------
NEW_OFF:    .byte 0,2,4,5,6,7,8,9,10,11,13,17,25,26
NEW_VAL:    .byte 1,9,200,200,200,200,200,230,6,6,2,64,200,3
NEW_N = 14

; ---------------- Byte ----------------
CAT_POSE:   .byte PC_WALKR1,PC_SIT,PC_SLEEP,PC_EAT

; ---------------- props: Zzz, notes, heart, bubbles, ball, ! ----------------
PROP_DX:    .byte 4,4,8,8,4,0,0,0,4
PROP_DY:    .byte $F6,$F6,$F2,$F2,$F0,$F8,$F8,$FA,$F0
PROP_CO:    .byte 15,15,15,15,8,15,15,10,11
PROP_AN:    .byte 1,0,1,0,0,1,0,0,0
BOUNCE:     .byte 0,4,7,10,12,13,14,14,13,12,10,7,4,2,1,0

; ---------------- the panel ----------------
FACE_T:     .byte T_HAPPY,T_FINE,T_SAD,T_SICK
MOOD_LO:    .byte <TM_0,<TM_1,<TM_2,<TM_3
MOOD_HI:    .byte >TM_0,>TM_1,>TM_2,>TM_3
TM_0:       .byte "HAPPY",0
TM_1:       .byte "FINE ",0
TM_2:       .byte "SAD  ",0
TM_3:       .byte "SICK ",0
TXT_DAYH:   .byte "DAY ",0
TXT_HINT:   .byte "BUTTON 1 = MENU",0
TXT_ARROWL: .byte "<  ",0
TXT_ARROWR: .byte "  >",0
TXT_LETOF:  .byte "LETTER OF DAY ",0
TXT_LABELS:
  .byte 20,0,"FOOD",0
  .byte 20,10,"DRINK",0
  .byte 20,21,"SLEEP",0
  .byte 21,0,"CLEAN",0
  .byte 21,10,"FUN",0
  .byte 21,21,"HEALTH",0
  .byte $FF

; ---------------- the menus ----------------
MENU_N:     .byte 8,6,12,4                     ; items: main, gifts, ask, letters (NLET)
MTITLE_LO:  .byte <TMT_0,<TMT_1,<TMT_2,<TMT_3
MTITLE_HI:  .byte >TMT_0,>TMT_1,>TMT_2,>TMT_3
TMT_0:      .byte "WHAT DO YOU DO?",0
TMT_1:      .byte "WHICH GIFT?",0
TMT_2:      .byte "ASK SIX TO...  (UP = PLEASE)",0
TMT_3:      .byte "WHICH LETTER?",0
TXT_MPLEASE: .byte "PLEASE, SIX, COULD YOU...",0
MLIST_LO:   .byte <ML_MAIN,<ML_GIFT,<ML_ASK
MLIST_HI:   .byte >ML_MAIN,>ML_GIFT,>ML_ASK
ML_MAIN:    .word MM_0,MM_1,MM_2,MM_3,MM_4,MM_5,MM_6,MM_7
ML_GIFT:    .word GIFT_0,GIFT_1,GIFT_2,GIFT_3,GIFT_4,GIFT_5
ML_ASK:     .word MA_0,MA_1,MA_2,MA_3,MA_4,MA_5,MA_6,MA_7,MA_8,MA_9,MA_10,MA_11
MM_0:       .byte "BRING FOOD",0
MM_1:       .byte "BRING WATER",0
MM_2:       .byte "FEED BYTE",0
MM_3:       .byte "SEND A GIFT",0
MM_4:       .byte "ASK SIX",0
MM_5:       .byte "KNOCK ON THE GLASS",0
MM_6:       .byte "READ LETTERS",0
MM_7:       .byte "SAVE AND QUIT",0
GIFT_0:     .byte "BOOK",0
GIFT_1:     .byte "RECORD",0
GIFT_2:     .byte "FLOWERS",0
GIFT_3:     .byte "CAKE",0
GIFT_4:     .byte "TEA",0
GIFT_5:     .byte "BALL",0
GIFTN_LO:   .byte <GIFT_0,<GIFT_1,<GIFT_2,<GIFT_3,<GIFT_4,<GIFT_5
GIFTN_HI:   .byte >GIFT_0,>GIFT_1,>GIFT_2,>GIFT_3,>GIFT_4,>GIFT_5
MA_0:       .byte "EAT",0
MA_1:       .byte "DRINK",0
MA_2:       .byte "GO TO BED",0
MA_3:       .byte "TAKE A BATH",0
MA_4:       .byte "READ A BOOK",0
MA_5:       .byte "PLAY MUSIC",0
MA_6:       .byte "EXERCISE",0
MA_7:       .byte "USE THE COMPUTER",0
MA_8:       .byte "PLAY HI-LO BITS",0
MA_9:       .byte "WRITE A LETTER",0
MA_10:      .byte "TINKER",0
MA_11:      .byte "PLAY BALL",0

; ---------------- what is said on row 22 ----------------
TX_HELLO = 0
TX_BACK = 1
TX_NOFOOD = 2
TX_NOWATER = 3
TX_NIGHT = 4
TX_MORNING = 5
TX_WROTE = 6
TX_CATHUNGRY = 7
TX_SICKBED = 8
TX_FULL = 9
TX_FOOD = 10
TX_FULLW = 11
TX_WATER = 12
TX_DLVSLEEP = 13
TX_BOWL = 14
TX_NOLET = 15
TX_ZZZ = 16
TX_STOPKNOCK = 17
TX_HI1 = 18
TX_HI2 = 19
TX_HI3 = 20
TX_HI4 = 21
TX_GIFTSLEEP = 22
TX_AGAIN = 23
TX_G0 = 24
TX_G1 = 25
TX_G2 = 26
TX_G3 = 27
TX_G4 = 28
TX_G5 = 29
TX_ALONE = 30
TX_DOING = 31
TX_TOOSICK = 32
TX_NOBALL = 33
TX_NO1 = 34
TX_NO2 = 35
TX_OK = 36
TX_PLEASURE = 37
TX_NOTTIRED = 38
TX_NOTHUNGRY = 39
TX_NOTTHIRSTY = 40
TX_CLEAN = 41
TX_HUNGRY = 42
TX_THIRSTY = 43
TX_TIRED = 44
TX_DIRTY = 45
TX_BORED = 46
TX_UNWELL = 47
TX_KNOCK = 48
TX_T1 = 49
TX_T2 = 50
TX_T3 = 51
TX_T4 = 52
TX_T5 = 53
TX_T6 = 54
TX_HMM = 55
HELLO_TX:   .byte TX_HI1,TX_HI2,TX_HI3,TX_HI4
GIFT_TX:    .byte TX_G0,TX_G1,TX_G2,TX_G3,TX_G4,TX_G5
NO_TX:      .byte TX_NO1,TX_NO2
TXT_LO:
  .byte <S_00,<S_01,<S_02,<S_03,<S_04,<S_05,<S_06,<S_07,<S_08,<S_09,<S_10,<S_11,<S_12,<S_13,<S_14,<S_15
  .byte <S_16,<S_17,<S_18,<S_19,<S_20,<S_21,<S_22,<S_23,<S_24,<S_25,<S_26,<S_27,<S_28,<S_29,<S_30,<S_31
  .byte <S_32,<S_33,<S_34,<S_35,<S_36,<S_37,<S_38,<S_39,<S_40,<S_41,<S_42,<S_43,<S_44,<S_45,<S_46,<S_47
  .byte <S_48,<S_49,<S_50,<S_51,<S_52,<S_53,<S_54,<S_55
TXT_HI:
  .byte >S_00,>S_01,>S_02,>S_03,>S_04,>S_05,>S_06,>S_07,>S_08,>S_09,>S_10,>S_11,>S_12,>S_13,>S_14,>S_15
  .byte >S_16,>S_17,>S_18,>S_19,>S_20,>S_21,>S_22,>S_23,>S_24,>S_25,>S_26,>S_27,>S_28,>S_29,>S_30,>S_31
  .byte >S_32,>S_33,>S_34,>S_35,>S_36,>S_37,>S_38,>S_39,>S_40,>S_41,>S_42,>S_43,>S_44,>S_45,>S_46,>S_47
  .byte >S_48,>S_49,>S_50,>S_51,>S_52,>S_53,>S_54,>S_55
S_00: .byte "SIX: I LIKE IT! I'M MOVING IN!",0
S_01: .byte "SIX: WELCOME BACK, FRIEND!",0
S_02: .byte "SIX: THE FRIDGE IS EMPTY!",0
S_03: .byte "SIX: THERE IS NO WATER LEFT!",0
S_04: .byte "SIX: GOOD NIGHT!",0
S_05: .byte "SIX: GOOD MORNING!",0
S_06: .byte "SIX: I WROTE YOU A LETTER!",0
S_07: .byte "SIX: BYTE IS HUNGRY!",0
S_08: .byte "SIX: I FEEL SICK. TO BED...",0
S_09: .byte "THE FRIDGE IS ALREADY FULL.",0
S_10: .byte "SIX: THANKS FOR THE SHOPPING!",0
S_11: .byte "THERE IS PLENTY OF WATER.",0
S_12: .byte "SIX: THANKS FOR THE WATER!",0
S_13: .byte "DELIVERED. SIX IS ASLEEP.",0
S_14: .byte "BYTE'S BOWL IS FULL.",0
S_15: .byte "NO LETTERS YET.",0
S_16: .byte "SIX: ZZZ... NOT NOW...",0
S_17: .byte "SIX: STOP KNOCKING!",0
S_18: .byte "SIX: HELLO THERE!",0
S_19: .byte "SIX: HI! NICE TO SEE YOU.",0
S_20: .byte "SIX: OH, IT'S YOU! HELLO!",0
S_21: .byte "SIX: HOW ARE YOU OUT THERE?",0
S_22: .byte "THE GIFT WAITS FOR THE MORNING.",0
S_23: .byte "SIX: ANOTHER ONE? WELL, THANKS.",0
S_24: .byte "SIX: A BOOK! THANK YOU!",0
S_25: .byte "SIX: A RECORD! LET'S DANCE!",0
S_26: .byte "SIX: WHAT LOVELY FLOWERS!",0
S_27: .byte "SIX: CAKE! YUMMY!",0
S_28: .byte "SIX: A NICE CUP OF TEA!",0
S_29: .byte "SIX: A BALL! GREAT!",0
S_30: .byte "SIX: LEAVE ME ALONE!",0
S_31: .byte "SIX: I AM DOING IT!",0
S_32: .byte "SIX: I FEEL TOO SICK.",0
S_33: .byte "SIX: I HAVE NO BALL.",0
S_34: .byte "SIX: NO, I DON'T FEEL LIKE IT.",0
S_35: .byte "SIX: MAYBE LATER.",0
S_36: .byte "SIX: OK!",0
S_37: .byte "SIX: WITH PLEASURE!",0
S_38: .byte "SIX: I AM NOT TIRED.",0
S_39: .byte "SIX: I AM NOT HUNGRY.",0
S_40: .byte "SIX: I AM NOT THIRSTY.",0
S_41: .byte "SIX: I AM CLEAN ALREADY.",0
S_42: .byte "SIX: I AM HUNGRY!",0
S_43: .byte "SIX: I AM THIRSTY!",0
S_44: .byte "SIX: I AM SO TIRED...",0
S_45: .byte "SIX: I NEED A BATH!",0
S_46: .byte "SIX: I AM BORED!",0
S_47: .byte "SIX: I DON'T FEEL WELL.",0
S_48: .byte "SIX: KNOCK KNOCK! ANYBODY HOME?",0
S_49: .byte "SIX: A SOFA AND RECORDS. NICE!",0
S_50: .byte "SIX: A KITCHEN! AND A FRIDGE!",0
S_51: .byte "SIX: A BATHTUB, TOO!",0
S_52: .byte "SIX: WOW! A COMPUTER!",0
S_53: .byte "SIX: WHAT A COMFY BED...",0
S_54: .byte "SIX: AND A WORKSHOP!",0
S_55: .byte "SIX: HMM... SHOULD I STAY?",0

; the visit of a new house (TOUR): where he stops, what he says, his pose and prop, how long
;              door     sofa     kitchen  bath     computer bed      workshop think    (he stays)
TOUR_F:     .byte 2,       2,       2,       1,       1,       0,       0,       0,       0
TOUR_X:     .byte 240,     184,     96,      72,      152,     92,      176,     176,     176
TOUR_TX:    .byte TX_KNOCK,TX_T1,   TX_T2,   TX_T3,   TX_T4,   TX_T5,   TX_T6,   TX_HMM,  $FF
TOUR_PO:    .byte $FF,     PO_FRONT,PO_FRONT,PO_FRONT,PO_FRONT,PO_FRONT,PO_FRONT,PO_FRONT
TOUR_PR:    .byte 0,       PR_EXCL, PR_EXCL, PR_EXCL, PR_EXCL, PR_EXCL, PR_EXCL, 0
TOUR_W:     .byte 150,     110,     110,     110,     110,     110,     110,     200

; ---------------- the title ----------------
TXT_TITLE:
  .byte 8,3,"SIX LIVES IN A TINY HOUSE ON",0
  .byte 9,3,"THE 6502 OF YOUR MINIVIC,",0
  .byte 10,3,"WITH BYTE, HIS BLACK CAT.",0
  .byte 12,3,"BRING FOOD AND WATER, SEND",0
  .byte 13,3,"GIFTS, ASK HIM NICELY, PLAY",0
  .byte 14,3,"HI-LO BITS, READ HIS LETTERS.",0
  .byte 23,3,"DEVELOPED BY BOOGS & CCAI",0
  .byte $FF
TXT_BTN2:
  .byte 20,5,"BUTTON 1 = CONTINUE",0
  .byte 21,5,"BUTTON 2 = NEW HOUSE",0
  .byte $FF
TXT_BTN1:
  .byte 20,5,"BUTTON = NEW HOUSE",0
  .byte $FF
TXT_SURE:
  .byte 18,1,"  BUTTON 2 AGAIN: A NEW HOUSE  ",0,$FF
TXT_NOSD:
  .byte 18,1,"NO SD CARD: THE HOUSE IS NOT SAVED",0,$FF
TXT_HDAY:   .byte "DAY ",0
TXT_HBEST:  .byte "  BEST HI-LO ",0
TXT_HOF10:  .byte "/10",0

; ---------------- HI-LO BITS ----------------
TXT_HL:
  .byte 1,11,"HI-LO BITS",0
  .byte 6,5,"HIGHER OR LOWER NEXT?",0
  .byte $FF
TXT_HLASK:
  .byte 15,0,"                                ",0
  .byte 16,0,"                                ",0
  .byte 18,0,"                                ",0
  .byte 20,2,"UP = HIGHER     DOWN = LOWER",0
  .byte 21,2,"BUTTON 2 = STOP",0
  .byte $FF
TXT_HLWAIT:
  .byte 20,0,"                                ",0
  .byte 21,0,"                                ",0
  .byte $FF
TXT_HLBACK:
  .byte 20,2,"BUTTON = BACK TO THE HOUSE",0,$FF
TXT_HLYOU:  .byte "YOU SAY:  ",0
TXT_HLSIXS: .byte "SIX SAYS: ",0
TXT_HLSC1:  .byte "YOU ",0
TXT_HLSC2:  .byte "   SIX ",0
TXT_HLSC3:  .byte "   ROUND ",0
HLWAY_LO:   .byte <TXT_LOWER,<TXT_HIGHER
HLWAY_HI:   .byte >TXT_LOWER,>TXT_HIGHER
TXT_LOWER:  .byte "LOWER ",0
TXT_HIGHER: .byte "HIGHER",0
TXT_HLSAME: .byte "  THE SAME NUMBER: NO POINTS",0
HLRES_LO:   .byte <HR_0,<HR_1,<HR_2,<HR_3
HLRES_HI:   .byte >HR_0,>HR_1,>HR_2,>HR_3
HR_0:       .byte "  NOBODY GOT IT!",0
HR_1:       .byte "  YOU GOT IT!",0
HR_2:       .byte "  SIX GOT IT!",0
HR_3:       .byte "  BOTH RIGHT!",0
TXT_HLWIN:  .byte "  YOU WIN! SIX: WELL PLAYED.",0
TXT_HLLOSE: .byte "  SIX WINS! SIX: HA HA, AGAIN?",0
TXT_HLDRAW: .byte "  A DRAW! SIX: LET'S PLAY AGAIN.",0

; ---------------- the letters ----------------
TXT_LFROM:  .byte "     A LETTER FROM SIX",0
TXT_LBACK:  .byte 22,2,"BUTTON = BACK",0,$FF
TXT_LDAY1:  .byte "IT IS DAY ",0
TXT_LDAY2:  .byte " IN MY HOUSE.",0
TXT_LTHANK: .byte "THANK YOU FOR THE ",0
TXT_LNOGIFT: .byte "NOBODY SENDS ME PRESENTS...",0
TXT_LCATH:  .byte "BYTE IS VERY HUNGRY!",0
TXT_LSIX:   .byte "SIX",0
GREET_LO:   .byte <LG_0,<LG_1,<LG_2,<LG_3
GREET_HI:   .byte >LG_0,>LG_1,>LG_2,>LG_3
LG_0:       .byte "DEAR FRIEND,",0
LG_1:       .byte "HELLO OUT THERE,",0
LG_2:       .byte "DEAR NEIGHBOUR,",0
LG_3:       .byte "HI THERE,",0
MOODL_LO:   .byte <LM_0,<LM_1,<LM_2,<LM_3,<LM_4,<LM_5,<LM_6,<LM_7
MOODL_HI:   .byte >LM_0,>LM_1,>LM_2,>LM_3,>LM_4,>LM_5,>LM_6,>LM_7
LM_0:       .byte "I AM VERY HAPPY TODAY!",0
LM_1:       .byte "LIFE IN THE CHIP IS GREAT.",0
LM_2:       .byte "THINGS ARE QUIET IN HERE.",0
LM_3:       .byte "TODAY WAS AN ORDINARY DAY.",0
LM_4:       .byte "I FEEL A BIT SAD TODAY.",0
LM_5:       .byte "IT IS LONELY IN HERE.",0
LM_6:       .byte "I DO NOT FEEL WELL AT ALL.",0
LM_7:       .byte "I AM ILL AND I STAY IN BED.",0
PERSL_LO:   .byte <LP_0,<LP_1,<LP_2,<LP_3,<LP_4,<LP_5
PERSL_HI:   .byte >LP_0,>LP_1,>LP_2,>LP_3,>LP_4,>LP_5
LP_0:       .byte "I FIXED THINGS IN MY SHOP.",0
LP_1:       .byte "I HAD A LOVELY LONG NAP.",0
LP_2:       .byte "I PLAYED MY RECORDS ALL DAY.",0
LP_3:       .byte "I RODE MY BIKE FOR HOURS.",0
LP_4:       .byte "I READ A WONDERFUL BOOK.",0
LP_5:       .byte "I DREAM OF A BIG CAKE.",0
CATL_LO:    .byte <LC_0,<LC_1
CATL_HI:    .byte >LC_0,>LC_1
LC_0:       .byte "BYTE IS A HAPPY CAT.",0
LC_1:       .byte "BYTE PURRS ALL DAY LONG.",0
WANTL_LO:   .byte <LW_0,<LW_1,<LW_2,<LW_3,<LW_4,<LW_5,<LW_6,<LW_7
WANTL_HI:   .byte >LW_0,>LW_1,>LW_2,>LW_3,>LW_4,>LW_5,>LW_6,>LW_7
LW_0:       .byte "COULD YOU BRING SOME FOOD?",0
LW_1:       .byte "I WOULD LOVE SOME WATER.",0
LW_2:       .byte "I NEED MORE SLEEP.",0
LW_3:       .byte "I REALLY NEED A BATH.",0
LW_4:       .byte "PLEASE PLAY HI-LO WITH ME!",0
LW_5:       .byte "A CUP OF TEA WOULD HELP.",0
LW_6:       .byte "PLEASE FEED BYTE!",0
LW_7:       .byte "I HAVE ALL I NEED.",0
HILOL_LO:   .byte <LH_0,<LH_1
HILOL_HI:   .byte >LH_0,>LH_1
LH_0:       .byte "I BEAT YOU AT HI-LO BITS!",0
LH_1:       .byte "YOU ARE GOOD AT HI-LO BITS.",0
BYE_LO:     .byte <LB_0,<LB_1,<LB_2,<LB_3
BYE_HI:     .byte >LB_0,>LB_1,>LB_2,>LB_3
LB_0:       .byte "YOUR FRIEND,",0
LB_1:       .byte "BEST WISHES,",0
LB_2:       .byte "BYE FOR NOW,",0
LB_3:       .byte "LOVE,",0

; ---------------------------------------------------------------
; music (engine from tank): per track 0 melody / 1 harmony / 2 bass
; ---------------------------------------------------------------
; melody, harmony, bass: 4 bytes per instrument (ENVO = 0 organ, 4 piano: hard attack, quick decay)
V0_TAB:        .byte 13, 9, 12, 0,  15, 11, 14, 0  ; volume at the attack of the note
FLOOR_TAB:     .byte 8, 5, 7, 0,    3, 2, 4, 0     ; lowest volume reached by the decay
DECMASK_TAB:   .byte 3, 7, 3, 0,    1, 3, 3, 0     ; the volume drops by 1 when (age AND mask) = 0
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
;  GRAPHICS, HOUSE AND SOUND TABLES (generated)
; ===============================================================
; LITTLE 6502 GUY: generated by dev/gen_little_6502_guy.js (do not edit by hand)

; sprite patterns: Six pose n = patterns 2n (overalls) and 2n+1 (skin); props one pattern each
PO_FRONT = 0
PO_WAVE1 = 1
PO_WAVE2 = 2
PO_WALKR1 = 3
PO_WALKR2 = 4
PO_WALKL1 = 5
PO_WALKL2 = 6
PO_CLIMB1 = 7
PO_CLIMB2 = 8
PO_SITR1 = 9
PO_SITR2 = 10
PO_LIE = 11
PO_BATH1 = 12
PO_BATH2 = 13
PO_DANCE1 = 14
PO_DANCE2 = 15
PO_READ = 16
PO_BIKE1 = 17
PO_BIKE2 = 18
PO_SAD = 19
PO_DRINK = 20
PO_HAMMER1 = 21
PO_HAMMER2 = 22
NPOSES = 23
PR_Z1 = 46
PR_Z2 = 47
PR_NOTE1 = 48
PR_NOTE2 = 49
PR_HEART = 50
PR_BUB1 = 51
PR_BUB2 = 52
PR_BALL = 53
PR_EXCL = 54
PC_WALKR1 = 55
PC_WALKR2 = 56
PC_WALKL1 = 57
PC_WALKL2 = 58
PC_SIT = 59
PC_SLEEP = 60
PC_EAT = 61
SPR_LEN = 1984
SPR_PAGES = 8
SPRITES:
  .byte $00,$03,$07,$04,$02,$00,$01,$00,$0F,$1F,$17,$07,$07,$06,$06,$0E,$00,$C0,$E0,$20,$40,$00,$80,$00,$F0,$F8,$E8,$E0,$E0,$60,$60,$70
  .byte $00,$00,$00,$03,$05,$07,$06,$01,$00,$00,$00,$10,$00,$00,$00,$00,$00,$00,$00,$C0,$A0,$E0,$60,$80,$00,$00,$00,$08,$00,$00,$00,$00
  .byte $00,$03,$07,$04,$02,$00,$01,$00,$0F,$1F,$17,$07,$07,$06,$06,$0E,$00,$C0,$E0,$20,$44,$04,$8C,$08,$F8,$F0,$E0,$E0,$E0,$60,$60,$70
  .byte $00,$00,$00,$03,$05,$07,$06,$01,$00,$00,$00,$10,$00,$00,$00,$00,$00,$00,$04,$C4,$A0,$E0,$60,$80,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$03,$07,$04,$02,$00,$01,$00,$0F,$1F,$17,$07,$07,$06,$06,$0E,$00,$C0,$E0,$28,$48,$08,$98,$10,$F0,$F0,$E0,$E0,$E0,$60,$60,$70
  .byte $00,$00,$00,$03,$05,$07,$06,$01,$00,$00,$00,$10,$00,$00,$00,$00,$00,$04,$04,$C0,$A0,$E0,$60,$80,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$03,$07,$07,$06,$04,$00,$00,$03,$07,$07,$07,$03,$06,$0C,$1C,$00,$C0,$E0,$00,$40,$00,$20,$00,$C0,$E0,$E0,$E0,$C0,$60,$30,$38
  .byte $00,$00,$00,$00,$01,$03,$03,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$F0,$B0,$F8,$C0,$80,$00,$00,$00,$10,$00,$00,$00,$00
  .byte $00,$03,$07,$07,$06,$04,$00,$00,$03,$07,$07,$03,$03,$03,$03,$03,$00,$C0,$E0,$00,$40,$00,$20,$00,$C0,$E0,$E0,$40,$C0,$C0,$C0,$E0
  .byte $00,$00,$00,$00,$01,$03,$03,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$F0,$B0,$F8,$C0,$80,$00,$00,$00,$80,$00,$00,$00,$00
  .byte $00,$03,$07,$00,$02,$00,$04,$00,$03,$07,$07,$07,$03,$06,$0C,$1C,$00,$C0,$E0,$E0,$60,$20,$00,$00,$C0,$E0,$E0,$E0,$C0,$60,$30,$38
  .byte $00,$00,$00,$0F,$0D,$1F,$03,$01,$00,$00,$00,$08,$00,$00,$00,$00,$00,$00,$00,$00,$80,$C0,$C0,$80,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$03,$07,$00,$02,$00,$04,$00,$03,$07,$07,$02,$03,$03,$03,$07,$00,$C0,$E0,$E0,$60,$20,$00,$00,$C0,$E0,$E0,$C0,$C0,$C0,$C0,$C0
  .byte $00,$00,$00,$0F,$0D,$1F,$03,$01,$00,$00,$00,$01,$00,$00,$00,$00,$00,$00,$00,$00,$80,$C0,$C0,$80,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$03,$17,$17,$17,$13,$1B,$08,$0F,$07,$07,$07,$07,$06,$06,$06,$00,$C0,$E0,$E0,$E0,$C0,$C0,$00,$F0,$F8,$E8,$E0,$E0,$60,$60,$00
  .byte $00,$10,$00,$00,$00,$04,$00,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$20,$00,$80,$00,$00,$00,$08,$00,$00,$00,$00
  .byte $00,$03,$07,$07,$07,$03,$03,$00,$0F,$1F,$17,$07,$07,$06,$06,$00,$00,$C0,$E8,$E8,$E8,$C8,$D8,$10,$F0,$E0,$E0,$E0,$E0,$60,$60,$60
  .byte $00,$00,$00,$00,$00,$04,$00,$01,$00,$00,$00,$10,$00,$00,$00,$00,$00,$08,$00,$00,$00,$20,$00,$80,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$03,$07,$07,$06,$04,$00,$00,$03,$07,$07,$07,$07,$00,$00,$00,$00,$C0,$E0,$00,$40,$00,$20,$00,$C0,$E0,$F0,$F8,$F8,$18,$38
  .byte $00,$00,$00,$00,$00,$01,$03,$03,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$F0,$B0,$F8,$C0,$80,$00,$00,$0C,$00,$00,$00,$00
  .byte $00,$00,$03,$07,$07,$06,$04,$00,$00,$03,$07,$07,$07,$07,$00,$00,$00,$00,$C0,$E0,$00,$40,$00,$20,$00,$C0,$E0,$E0,$F8,$F8,$18,$38
  .byte $00,$00,$00,$00,$00,$01,$03,$03,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$F0,$B0,$F8,$C0,$80,$00,$00,$18,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$70,$E0,$C0,$B0,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$1C,$3E,$4E,$7C,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$80,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$03,$07,$04,$02,$00,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$C0,$E0,$20,$40,$00,$80,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$03,$05,$07,$06,$01,$0F,$1F,$17,$00,$00,$00,$00,$00,$00,$00,$00,$C0,$A0,$E0,$60,$80,$F4,$FC,$E0,$00,$00,$00
  .byte $00,$00,$00,$03,$07,$04,$02,$00,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$C0,$E0,$20,$40,$00,$80,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$03,$05,$07,$06,$01,$2F,$3F,$07,$00,$00,$00,$00,$00,$00,$00,$00,$C0,$A0,$E0,$60,$80,$F0,$F8,$E8,$00,$00,$00
  .byte $00,$13,$17,$14,$12,$18,$01,$00,$0F,$07,$07,$07,$07,$06,$06,$0E,$00,$C0,$E0,$20,$40,$00,$98,$08,$F0,$E0,$E0,$E0,$E0,$78,$00,$00
  .byte $10,$00,$00,$03,$05,$07,$06,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$C0,$A0,$E0,$64,$84,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$03,$07,$04,$02,$00,$19,$10,$0F,$07,$07,$07,$07,$1E,$00,$00,$00,$C8,$E8,$28,$48,$18,$80,$00,$F0,$E0,$E0,$E0,$E0,$60,$60,$70
  .byte $00,$00,$00,$03,$05,$07,$26,$21,$00,$00,$00,$00,$00,$00,$00,$00,$08,$00,$00,$C0,$A0,$E0,$60,$80,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$03,$07,$04,$02,$00,$01,$00,$0F,$1F,$0F,$0F,$06,$06,$0E,$00,$00,$C0,$E0,$20,$40,$00,$80,$00,$F0,$F8,$F0,$F0,$60,$60,$70
  .byte $00,$00,$00,$00,$03,$05,$07,$06,$01,$00,$00,$10,$00,$00,$00,$00,$00,$00,$00,$00,$C0,$A0,$E0,$60,$80,$00,$00,$08,$00,$00,$00,$00
  .byte $00,$00,$03,$07,$07,$06,$04,$00,$00,$03,$07,$07,$07,$07,$01,$00,$00,$00,$C0,$E0,$00,$40,$00,$20,$00,$C0,$E0,$F0,$F8,$60,$80,$00
  .byte $00,$00,$00,$00,$00,$01,$03,$03,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$F0,$B0,$F8,$C0,$80,$00,$00,$0C,$00,$00,$00,$00
  .byte $00,$00,$03,$07,$07,$06,$04,$00,$00,$03,$07,$07,$07,$07,$06,$00,$00,$00,$C0,$E0,$00,$40,$00,$20,$00,$C0,$E0,$F0,$F8,$E0,$00,$00
  .byte $00,$00,$00,$00,$00,$01,$03,$03,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$F0,$B0,$F8,$C0,$80,$00,$00,$0C,$00,$00,$00,$00
  .byte $00,$00,$03,$07,$04,$00,$02,$00,$01,$0F,$1F,$17,$07,$07,$06,$0E,$00,$00,$C0,$E0,$20,$00,$40,$00,$80,$F0,$F8,$E8,$E0,$E0,$60,$70
  .byte $00,$00,$00,$00,$03,$07,$05,$07,$02,$00,$00,$00,$10,$00,$00,$00,$00,$00,$00,$00,$C0,$E0,$A0,$E0,$40,$00,$00,$00,$08,$00,$00,$00
  .byte $00,$03,$07,$30,$32,$20,$24,$00,$07,$07,$07,$03,$03,$03,$03,$07,$00,$C0,$E0,$E0,$60,$20,$00,$00,$C0,$E0,$E0,$C0,$C0,$C0,$C0,$C0
  .byte $00,$00,$00,$0F,$0D,$1F,$1B,$0D,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$80,$C0,$C0,$80,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$03,$07,$07,$07,$03,$03,$00,$0F,$1F,$17,$07,$07,$06,$06,$0E,$0C,$CC,$E0,$E8,$E8,$C8,$C8,$10,$F0,$F0,$E0,$E0,$E0,$60,$60,$70
  .byte $00,$00,$00,$00,$00,$04,$00,$01,$00,$00,$00,$10,$00,$00,$00,$00,$00,$00,$08,$00,$00,$20,$00,$80,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$03,$07,$07,$07,$03,$03,$00,$0F,$1F,$17,$07,$07,$06,$06,$0E,$00,$C0,$E0,$E0,$E0,$C0,$C0,$00,$F0,$F8,$E8,$E6,$E6,$60,$60,$70
  .byte $00,$00,$00,$00,$00,$04,$00,$01,$00,$00,$00,$10,$00,$00,$00,$00,$00,$00,$00,$00,$00,$20,$00,$80,$00,$00,$00,$08,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$03,$01,$03,$00,$00,$00,$00,$00,$00,$00,$00,$3C,$08,$10,$3C,$00,$80,$00,$80,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$01,$00,$00,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$1C,$08,$1C,$E0,$40,$80,$E0,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$01,$03,$01,$00,$00,$00,$00,$00,$00,$00,$00,$60,$50,$48,$40,$40,$C0,$C0,$80,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $07,$04,$04,$04,$1C,$3C,$18,$00,$00,$00,$00,$00,$00,$00,$00,$00,$F0,$10,$10,$10,$70,$F0,$60,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$36,$7F,$7F,$3E,$1C,$08,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$18,$24,$18,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$18,$24,$24,$18,$00,$08,$14,$08,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$60,$90,$60,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$60,$90,$90,$60,$00,$04,$0A,$04,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$03,$07,$07,$07,$07,$03,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$C0,$E0,$E0,$E0,$E0,$C0,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $01,$01,$01,$01,$01,$00,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$80,$80,$80,$80,$80,$00,$80,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$80,$40,$3F,$3F,$3F,$28,$44,$42,$00,$00,$00,$00,$00,$00,$05,$07,$0F,$0E,$F4,$F8,$F0,$28,$44,$82
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$C0,$3F,$3F,$3F,$14,$14,$12,$00,$00,$00,$00,$00,$00,$05,$07,$0F,$0E,$F4,$F8,$F0,$50,$50,$48
  .byte $00,$00,$00,$00,$00,$00,$A0,$E0,$F0,$70,$2F,$1F,$0F,$14,$22,$41,$00,$00,$00,$00,$00,$00,$00,$00,$01,$02,$FC,$FC,$FC,$14,$22,$42
  .byte $00,$00,$00,$00,$00,$00,$A0,$E0,$F0,$70,$2F,$1F,$0F,$0A,$0A,$12,$00,$00,$00,$00,$00,$00,$00,$00,$00,$03,$FC,$FC,$FC,$28,$28,$48
  .byte $00,$00,$00,$00,$00,$00,$05,$07,$07,$07,$0F,$0F,$0F,$0F,$0F,$05,$00,$00,$00,$00,$00,$00,$00,$00,$00,$80,$C0,$C0,$E0,$EC,$F4,$B8
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$0A,$1F,$3F,$7F,$7F,$3F,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$80,$F0,$F8,$F4,$F4
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$3F,$7F,$BF,$50,$E0,$40,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$F0,$F0,$F0,$28,$28,$28

; tiles of the house per third (59 / 94 / 42) and 65 shared tiles (191-255): patterns and colours
TP0A:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$07,$00,$07,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$03,$07,$0F,$E0,$80
  .byte $C0,$80,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$81,$81,$81,$00,$81,$81,$81,$00,$08,$08,$80,$08,$08,$C1,$08,$08
  .byte $03,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$C0,$E0,$0F,$07,$01,$00,$00,$00,$70,$80,$70,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01
  .byte $00,$01,$03,$0F,$E0,$C0,$80,$00,$00,$80,$C0,$0F,$07,$03,$01,$00,$00,$00,$00,$00,$00,$00,$00,$80,$00,$00,$00,$00,$00,$08,$08,$08
  .byte $80,$80,$80,$00,$08,$08,$08,$00,$00,$00,$00,$00,$00,$00,$00,$00,$42,$42,$81,$42,$42,$42,$81,$42,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $08,$08,$08,$08,$08,$08,$08,$08,$00,$30,$30,$30,$78,$78,$30,$00,$00,$1E,$06,$06,$06,$06,$00,$00,$01,$01,$07,$01,$01,$01,$00,$00
  .byte $80,$80,$E0,$80,$80,$80,$40,$00,$00,$00,$00,$00,$00,$00,$0F,$00,$00,$00,$00,$00,$00,$00,$00,$20,$C0,$C0,$C0,$C0,$C0,$C0,$C0,$C0
  .byte $00,$00,$00,$00,$00,$00,$03,$03,$00,$81,$81,$81,$81,$81,$81,$81,$00,$00,$00,$00,$00,$00,$00,$00
TC0A:
  .byte $0C,$0C,$0C,$0C,$0A,$0C,$0C,$0C,$0C,$0C,$0C,$AC,$0A,$AC,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$6C,$8C,$8C,$C8,$C6
  .byte $C8,$C8,$08,$06,$08,$08,$08,$06,$08,$08,$08,$06,$08,$08,$08,$06,$86,$86,$86,$06,$86,$86,$86,$06,$F8,$F8,$8F,$F6,$F8,$8F,$F8,$F6
  .byte $C8,$C8,$08,$06,$08,$08,$08,$06,$0C,$0C,$0C,$6C,$8C,$C8,$C8,$C6,$0C,$0C,$0C,$AC,$CA,$AC,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$6C
  .byte $0C,$8C,$8C,$6C,$C8,$C8,$C8,$06,$0C,$8C,$8C,$C6,$C8,$C8,$C8,$06,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$6C,$0C,$0C,$0C,$0C,$0A,$AC,$AC,$AC
  .byte $68,$68,$68,$06,$68,$68,$68,$06,$05,$05,$05,$05,$05,$05,$05,$05,$65,$65,$56,$65,$65,$65,$56,$65,$0E,$0E,$0E,$0E,$0E,$0E,$0E,$0E
  .byte $AC,$AC,$AC,$AC,$AC,$AC,$AC,$AC,$0E,$1E,$1E,$1E,$1E,$1E,$1E,$0E,$0E,$1E,$1E,$1E,$1E,$1E,$0E,$0E,$1E,$1E,$1E,$1E,$1E,$1E,$0E,$0E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$0E,$0C,$0C,$0C,$0C,$0C,$0C,$AC,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0A,$AC,$A5,$A5,$A5,$A5,$A5,$AF,$AF,$AF
  .byte $05,$05,$05,$05,$05,$05,$A5,$A5,$06,$61,$61,$61,$61,$61,$61,$61,$0E,$0E,$0E,$0E,$0E,$0E,$0E,$0A
TP0B:
  .byte $00,$00,$C0,$06,$06,$06,$07,$06,$00,$00,$00,$00,$00,$00,$01,$06,$20,$20,$20,$20,$20,$20,$20,$20,$00,$00,$80,$80,$00,$80,$86,$00
  .byte $00,$00,$01,$01,$00,$01,$01,$00,$C0,$C0,$C0,$C0,$C0,$C0,$C0,$C0,$00,$00,$00,$40,$00,$00,$00,$00,$00,$00,$00,$20,$00,$00,$00,$00
  .byte $00,$00,$00,$10,$00,$00,$00,$00,$03,$03,$03,$03,$03,$03,$03,$03,$81,$81,$81,$81,$81,$81,$81,$81,$00,$60,$60,$80,$60,$60,$60,$60
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$18,$18,$03,$18,$18,$18,$18,$06,$0F,$19,$19,$0F,$06,$C0,$30,$06,$06,$86,$86,$06,$06,$01,$06
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$80,$80,$80,$00,$00,$00,$00,$42,$42,$81,$42,$42,$42,$81,$42,$00,$00,$00,$00,$00,$08,$08,$08
  .byte $00,$81,$81,$81,$81,$81,$81,$00,$00,$81,$81,$91,$81,$81,$81,$00,$00,$81,$81,$81,$91,$81,$81,$00,$00,$81,$81,$89,$81,$81,$81,$00
  .byte $00,$81,$81,$81,$89,$81,$81,$00,$00,$00,$42,$00,$10,$10,$1C,$00,$00,$00,$82,$00,$10,$10,$1C,$00,$00,$00,$44,$00,$10,$10,$1C,$00
TC0B:
  .byte $0E,$0E,$E1,$1E,$1E,$1E,$1E,$1E,$0E,$0E,$0E,$0E,$0E,$0E,$E1,$1E,$AC,$AC,$AC,$AC,$AC,$AC,$AC,$AC,$05,$0A,$A6,$A6,$0A,$A6,$A6,$0A
  .byte $05,$0A,$A6,$A6,$0A,$A6,$A6,$0A,$AF,$A8,$A8,$A8,$A8,$AE,$A5,$A5,$05,$08,$08,$F8,$08,$0E,$05,$05,$05,$08,$08,$F8,$08,$0E,$05,$05
  .byte $05,$08,$08,$F8,$08,$0E,$05,$05,$A5,$A8,$A8,$A8,$A8,$AE,$A5,$A5,$61,$61,$61,$61,$61,$61,$61,$61,$0A,$6E,$6E,$E6,$6E,$6E,$6E,$6E
  .byte $0A,$0E,$0E,$06,$0E,$0E,$0E,$0E,$0A,$6E,$6E,$E6,$6E,$6E,$6E,$6E,$1E,$1E,$1E,$1E,$1E,$1E,$E1,$1E,$1E,$1E,$1E,$1E,$1E,$1E,$E1,$1E
  .byte $0B,$0A,$0A,$0A,$06,$0A,$0A,$0A,$0B,$6A,$6A,$6A,$06,$0A,$0A,$0A,$61,$61,$16,$61,$61,$61,$16,$61,$0B,$0A,$0A,$0A,$06,$6A,$6A,$6A
  .byte $0F,$F7,$F7,$F7,$F7,$F7,$F7,$0F,$0F,$F4,$F4,$F4,$F4,$F4,$F4,$0F,$0F,$F4,$F4,$F4,$F4,$F4,$F4,$0F,$0F,$F4,$F4,$F4,$F4,$F4,$F4,$0F
  .byte $0F,$F4,$F4,$F4,$F4,$F4,$F4,$0F,$05,$05,$F5,$0F,$1F,$1F,$1F,$0F,$05,$05,$F5,$0F,$1F,$1F,$1F,$0F,$05,$05,$F5,$0F,$1F,$1F,$1F,$0F
TP1A:
  .byte $08,$08,$08,$08,$08,$08,$08,$08,$00,$00,$00,$00,$00,$00,$00,$00,$80,$80,$80,$00,$08,$08,$08,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $42,$42,$81,$42,$42,$42,$81,$42,$00,$00,$00,$00,$00,$80,$90,$88,$00,$00,$00,$00,$00,$01,$03,$01,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$80,$55,$80,$55,$80,$00,$00,$00,$01,$56,$01,$56,$01,$00,$00,$00,$00,$00,$00,$00,$00,$20,$20,$20,$20,$00,$20,$20,$20
  .byte $08,$08,$08,$08,$08,$1C,$1C,$1C,$80,$80,$80,$00,$00,$00,$00,$00,$03,$21,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $20,$20,$20,$20,$20,$20,$20,$20,$00,$81,$81,$81,$81,$81,$81,$81,$0F,$0F,$0F,$0F,$0F,$0F,$C0,$C0,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $0F,$0F,$0F,$0F,$0F,$0F,$03,$03,$0F,$E0,$E0,$00,$15,$00,$00,$00,$0F,$07,$07,$00,$54,$00,$00,$00,$E0,$C0,$C0,$C0,$E0,$0F,$0C,$0C
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$07,$03,$03,$03,$07,$0F,$30,$30,$00,$80,$C0,$03,$03,$03,$03,$0F,$00,$01,$03,$C0,$C0,$C0,$C0,$0F
  .byte $81,$81,$81,$81,$81,$81,$81,$81,$03,$03,$03,$03,$80,$63,$63,$63,$00,$00,$60,$60,$60,$60,$60,$60
TC1A:
  .byte $AC,$AC,$AC,$AC,$AC,$AC,$AC,$AC,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$68,$68,$68,$06,$68,$68,$68,$06,$07,$07,$07,$07,$07,$07,$07,$07
  .byte $67,$67,$76,$67,$67,$67,$76,$67,$07,$07,$07,$07,$0F,$F5,$F5,$F5,$07,$07,$07,$07,$0F,$F5,$F5,$F5,$0A,$0A,$0A,$0A,$0A,$0A,$0A,$0A
  .byte $0A,$0A,$01,$1E,$E1,$1E,$E1,$1E,$0A,$0A,$01,$1E,$E1,$1E,$E1,$1E,$0C,$0C,$0C,$0C,$0A,$0C,$0C,$0C,$AC,$AC,$AC,$AC,$0A,$AC,$AC,$AC
  .byte $AC,$AC,$AC,$AC,$AC,$AC,$AC,$AC,$F5,$F5,$F5,$0F,$07,$07,$07,$07,$F5,$F5,$F5,$0F,$07,$07,$07,$07,$01,$0A,$0A,$0A,$0A,$0A,$0A,$0A
  .byte $AC,$AC,$AC,$AC,$AC,$AC,$AC,$AC,$06,$61,$61,$61,$61,$61,$61,$61,$EA,$EA,$EA,$EA,$EA,$EA,$AE,$AE,$0E,$0E,$0E,$0E,$0E,$0E,$0E,$0E
  .byte $AE,$AE,$AE,$AE,$AE,$AE,$AE,$AE,$EA,$AE,$1E,$01,$E1,$01,$01,$01,$AE,$AE,$1E,$01,$E1,$01,$01,$01,$7F,$7F,$7F,$7F,$7F,$F7,$F7,$F7
  .byte $0F,$0F,$0F,$0F,$0F,$0F,$07,$07,$7F,$7F,$7F,$7F,$7F,$7F,$F7,$F7,$0F,$7F,$7F,$F7,$F7,$F7,$F7,$F7,$0F,$7F,$7F,$F7,$F7,$F7,$F7,$7F
  .byte $61,$61,$61,$61,$61,$61,$61,$61,$6A,$6A,$6A,$6A,$A6,$6A,$6A,$6A,$0A,$0A,$6A,$6A,$6A,$6A,$6A,$6A
TP1B:
  .byte $00,$00,$06,$06,$06,$06,$06,$06,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$07,$08,$08,$08,$08,$08,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$80,$80,$80,$00,$00,$00,$00,$42,$42,$81,$42,$42,$42,$81,$42,$00,$00,$00,$00,$00,$08,$08,$08,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $42,$42,$81,$42,$42,$42,$81,$42,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$06,$06,$06,$00,$00,$00,$C0,$80,$00,$03,$03,$03,$03,$03
  .byte $03,$01,$00,$C0,$C0,$C0,$C0,$C0,$00,$00,$00,$00,$00,$00,$00,$00,$00,$80,$80,$80,$80,$80,$80,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$01,$01,$01,$01,$01,$01,$00,$20,$20,$20,$70,$70,$70,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$06,$06,$06,$06,$00
  .byte $80,$80,$80,$80,$80,$80,$80,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$01,$01,$01,$01,$01,$01,$00,$00,$00,$00,$00,$00,$00,$0F,$08
  .byte $00,$00,$00,$00,$00,$00,$00,$01,$08,$08,$08,$08,$08,$08,$08,$C8,$00,$00,$00,$00,$00,$00,$00,$00,$C0,$80,$80,$80,$00,$00,$00,$00
  .byte $03,$01,$01,$01,$00,$00,$00,$00,$00,$00,$00,$80,$80,$80,$78,$80,$00,$00,$00,$01,$01,$01,$1E,$01,$80,$80,$80,$80,$80,$80,$80,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$01,$01,$01,$01,$01,$01,$01,$00,$00,$00,$00,$00,$02,$00,$01,$00,$00,$81,$81,$81,$81,$81,$81,$00
  .byte $00,$81,$81,$91,$81,$81,$81,$00,$00,$81,$81,$81,$91,$81,$81,$00,$00,$81,$81,$89,$81,$81,$81,$00,$00,$81,$81,$81,$89,$81,$81,$00
  .byte $00,$00,$00,$06,$36,$36,$00,$00,$00,$00,$00,$30,$36,$36,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$10,$02,$21,$C0,$00,$00
  .byte $00,$00,$88,$21,$08,$00,$00,$00,$00,$00,$60,$68,$64,$03,$00,$00,$00,$00,$11,$08,$C0,$04,$00,$00,$00,$00,$0B,$43,$00,$43,$00,$00
  .byte $00,$00,$40,$20,$03,$10,$00,$00,$00,$00,$00,$80,$80,$80,$78,$80,$04,$04,$00,$01,$01,$01,$1E,$01,$18,$00,$00,$80,$80,$80,$78,$80
  .byte $18,$06,$00,$80,$80,$80,$78,$80,$00,$00,$00,$06,$06,$0E,$0E,$0E,$00,$00,$00,$06,$06,$11,$11,$11,$00,$00,$00,$00,$00,$03,$03,$03
  .byte $00,$00,$00,$18,$18,$44,$44,$44,$48,$03,$58,$38,$10,$38,$38,$38,$00,$00,$40,$28,$10,$38,$38,$38,$00,$00,$00,$00,$0F,$0F,$0F,$0F
  .byte $00,$00,$00,$00,$0F,$0F,$0F,$0F,$00,$0F,$0F,$0F,$0F,$0F,$0F,$0F,$00,$0F,$0F,$0F,$0F,$0F,$0F,$0F
TC1B:
  .byte $0A,$0A,$6A,$6A,$6A,$6A,$6A,$6A,$0C,$0C,$0A,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$CA,$AC,$AC,$AC,$AC,$AC,$0B,$0A,$0A,$0A,$06,$0A,$0A,$0A
  .byte $0B,$6A,$6A,$6A,$06,$0A,$0A,$0A,$61,$61,$16,$61,$61,$61,$16,$61,$0B,$0A,$0A,$0A,$06,$6A,$6A,$6A,$0B,$0B,$0B,$0B,$0B,$0B,$0B,$0B
  .byte $6B,$6B,$B6,$6B,$6B,$6B,$B6,$6B,$0F,$0F,$0F,$0F,$0F,$0F,$0F,$0F,$0F,$0F,$EF,$EF,$EF,$0F,$0F,$0F,$BE,$BE,$0E,$EB,$EB,$EB,$EB,$EB
  .byte $BE,$BE,$0E,$EB,$EB,$EB,$EB,$EB,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0A,$A4,$A4,$A4,$A4,$A4,$A4,$0A,$0A,$0B,$0B,$0B,$0B,$0B,$0B,$0A
  .byte $0A,$A4,$A4,$A4,$A4,$A4,$A4,$0A,$AC,$AC,$AC,$AC,$AC,$AC,$0C,$0C,$0F,$0E,$0F,$0F,$0F,$0F,$0F,$0F,$0F,$0E,$0F,$EF,$EF,$EF,$EF,$0F
  .byte $AD,$A2,$A2,$A2,$A2,$A2,$A2,$0A,$0D,$08,$08,$08,$08,$08,$08,$0A,$AD,$A2,$A2,$A2,$A2,$A2,$A2,$0A,$0C,$0C,$0C,$0C,$0C,$0C,$AC,$AC
  .byte $0C,$0C,$0C,$0C,$0C,$0C,$0C,$AC,$AC,$AC,$AC,$AC,$AC,$AC,$AC,$AC,$0B,$0B,$0B,$0B,$0B,$0B,$01,$01,$DC,$DC,$DC,$DC,$0C,$0C,$0C,$0C
  .byte $DC,$DC,$DC,$DC,$0C,$0C,$0C,$0C,$0D,$0D,$0A,$A6,$A6,$A6,$6A,$A6,$0D,$0D,$0A,$A6,$A6,$A6,$6A,$A6,$AD,$A8,$A8,$A8,$A8,$A8,$A8,$0A
  .byte $0D,$0F,$0F,$0F,$0F,$0F,$0F,$0A,$AD,$AB,$AB,$AB,$AB,$AB,$AB,$0A,$06,$06,$06,$06,$A6,$06,$86,$06,$0F,$F7,$F7,$F7,$F7,$F7,$F7,$0F
  .byte $0F,$F4,$F4,$F4,$F4,$F4,$F4,$0F,$0F,$F4,$F4,$F4,$F4,$F4,$F4,$0F,$0F,$F4,$F4,$F4,$F4,$F4,$F4,$0F,$0F,$F4,$F4,$F4,$F4,$F4,$F4,$0F
  .byte $0B,$0B,$0B,$8B,$8B,$8B,$01,$01,$0B,$0B,$0B,$8B,$8B,$8B,$01,$01,$0A,$01,$01,$01,$01,$01,$01,$0A,$0A,$01,$31,$31,$31,$13,$01,$0A
  .byte $0A,$01,$31,$31,$31,$03,$01,$0A,$0A,$01,$31,$31,$31,$13,$01,$0A,$0A,$01,$31,$31,$13,$31,$01,$0A,$0A,$01,$31,$31,$03,$31,$01,$0A
  .byte $0A,$01,$31,$31,$13,$31,$01,$0A,$01,$01,$0A,$A6,$A6,$A6,$6A,$A6,$E1,$E1,$0A,$A6,$A6,$A6,$6A,$A6,$F1,$01,$0A,$A6,$A6,$A6,$6A,$A6
  .byte $F1,$F1,$0A,$A6,$A6,$A6,$6A,$A6,$07,$07,$07,$F7,$F7,$F7,$F7,$F7,$07,$07,$07,$F7,$F7,$7F,$7F,$7F,$07,$07,$07,$07,$07,$F7,$F7,$F7
  .byte $07,$07,$07,$F7,$F7,$7F,$7F,$7F,$8B,$B8,$8B,$8B,$2B,$AB,$AB,$AB,$0B,$0B,$2B,$2B,$2B,$AB,$AB,$AB,$0A,$0A,$0A,$0A,$FA,$FA,$FA,$FA
  .byte $0A,$0A,$0A,$0A,$AF,$AF,$AF,$AF,$0A,$FA,$FA,$FA,$FA,$FA,$FA,$FA,$0A,$AF,$AF,$AF,$AF,$AF,$AF,$AF
TP2A:
  .byte $00,$01,$00,$00,$00,$00,$00,$00,$C8,$C8,$08,$08,$08,$08,$08,$08,$80,$80,$80,$00,$08,$08,$08,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $42,$42,$81,$42,$42,$42,$81,$42,$00,$00,$00,$00,$00,$00,$00,$60,$00,$00,$00,$00,$00,$00,$00,$06,$00,$6C,$00,$00,$C0,$20,$C0,$00
  .byte $00,$36,$00,$00,$03,$04,$03,$00,$06,$06,$06,$06,$01,$39,$39,$39,$00,$00,$30,$30,$30,$30,$30,$78,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$0C,$0C,$0C,$0C,$0C,$1E,$81,$81,$81,$81,$81,$81,$81,$81,$00,$00,$00,$00,$00,$60,$60,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$06,$06,$00,$00,$00,$00,$00,$00,$00,$00,$00,$80,$80,$80,$80,$80,$00,$60,$60,$01,$01,$01,$01,$01,$00,$06,$06
  .byte $80,$80,$80,$80,$80,$80,$80,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$01,$01,$01,$01,$01,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$C1,$C1,$C1,$08,$08,$08,$08,$08,$08,$08,$08,$08,$08,$08,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$80,$80,$80,$00,$00,$00,$00,$00,$00,$00,$00,$00,$08,$08,$08,$08,$08,$08,$1C,$1C,$1C,$00,$00
TC2A:
  .byte $0A,$AC,$0C,$0C,$0C,$0C,$0C,$0C,$AC,$AC,$AC,$AC,$AC,$AC,$AC,$AC,$68,$68,$68,$06,$68,$68,$68,$06,$0B,$0B,$0B,$0B,$0B,$0B,$0B,$0B
  .byte $6B,$6B,$B6,$6B,$6B,$6B,$B6,$6B,$0F,$0F,$0F,$0F,$0F,$0F,$0E,$EB,$0F,$0F,$0F,$0F,$0F,$0F,$0E,$EB,$0E,$1E,$0E,$0E,$E1,$1E,$E1,$0E
  .byte $0E,$1E,$0E,$0E,$E1,$1E,$E1,$0E,$6B,$6B,$6B,$6B,$B6,$B6,$B6,$B6,$06,$06,$6B,$6B,$6B,$6B,$6B,$6B,$06,$06,$0B,$0B,$0B,$0B,$0B,$0B
  .byte $06,$06,$6B,$6B,$6B,$6B,$6B,$6B,$61,$61,$61,$61,$61,$61,$61,$61,$0C,$0C,$0C,$0C,$0C,$CD,$CD,$0D,$0C,$0C,$0C,$0C,$0C,$0D,$0D,$0D
  .byte $0C,$0C,$0C,$0C,$0C,$CD,$CD,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$A6,$A6,$A6,$A6,$A6,$0A,$AD,$AD,$A6,$A6,$A6,$A6,$A6,$0A,$AD,$AD
  .byte $AD,$A4,$A4,$A4,$A4,$A4,$A4,$0A,$0D,$0B,$0B,$0B,$0B,$0B,$0B,$0A,$AD,$A4,$A4,$A4,$A4,$A4,$A4,$0A,$06,$06,$06,$06,$06,$06,$06,$06
  .byte $0C,$0C,$CE,$CE,$CE,$EC,$EC,$EC,$AC,$AC,$AC,$AC,$AC,$AC,$AC,$AC,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0C,$0B,$0A,$0A,$0A,$06,$0A,$0A,$0A
  .byte $0B,$6A,$6A,$6A,$06,$0A,$0A,$0A,$0B,$0A,$0A,$0A,$06,$6A,$6A,$6A,$AC,$AC,$AC,$AC,$AC,$AC,$0C,$0C
TP2B:
  .byte $00,$00,$00,$30,$30,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$38,$40,$80,$0F,$88,$88,$70,$00,$07,$80,$0F,$08,$08,$88,$70,$00
  .byte $70,$88,$98,$A8,$C8,$88,$70,$00,$70,$88,$08,$30,$40,$80,$07,$00,$3C,$3C,$3C,$3C,$3C,$3C,$00,$00,$08,$08,$08,$08,$08,$1C,$1C,$1C
  .byte $0E,$0F,$C1,$C1,$C1,$08,$08,$08,$00,$00,$00,$00,$00,$01,$83,$00,$00,$00,$00,$00,$5A,$01,$83,$00
TC2B:
  .byte $01,$01,$01,$E1,$E1,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$E1,$E1,$E1,$1E,$E1,$E1,$E1,$01,$1E,$E1,$1E,$E1,$E1,$E1,$E1,$01
  .byte $E1,$E1,$E1,$E1,$E1,$E1,$E1,$01,$E1,$E1,$E1,$E1,$E1,$E1,$1E,$01,$EC,$EC,$EC,$EC,$EC,$EC,$0C,$0C,$AC,$AC,$AC,$AC,$AC,$AC,$AC,$AC
  .byte $8C,$8C,$CE,$CE,$CE,$EC,$EC,$EC,$0B,$0B,$0B,$0B,$0B,$B8,$B8,$0B,$0B,$0B,$0B,$0B,$AB,$B8,$B8,$0B
TPSH:
  .byte $00,$18,$18,$18,$18,$60,$60,$80,$00,$18,$18,$18,$18,$06,$06,$01,$00,$78,$78,$18,$18,$F8,$F8,$00,$18,$18,$18,$18,$18,$07,$07,$00
  .byte $00,$F8,$F8,$00,$00,$00,$00,$00,$00,$07,$07,$18,$18,$18,$18,$18,$01,$06,$06,$18,$18,$1F,$1F,$00,$00,$E0,$E0,$18,$18,$18,$18,$E0
  .byte $00,$07,$07,$18,$18,$00,$00,$01,$98,$18,$18,$18,$18,$E0,$E0,$00,$19,$1E,$1E,$18,$18,$07,$07,$00,$00,$E0,$E0,$18,$18,$78,$78,$98
  .byte $00,$07,$07,$18,$18,$18,$18,$19,$18,$18,$18,$18,$18,$E0,$E0,$00,$00,$00,$00,$18,$18,$07,$07,$00,$00,$F8,$F8,$00,$00,$E0,$E0,$18
  .byte $00,$1F,$1F,$18,$18,$1F,$1F,$00,$E0,$18,$18,$18,$18,$E0,$E0,$00,$1F,$18,$18,$18,$18,$07,$07,$00,$00,$01,$01,$06,$06,$18,$18,$1F
  .byte $E0,$00,$00,$00,$00,$F8,$F8,$00,$1F,$18,$18,$18,$18,$1F,$1F,$00,$00,$F8,$F8,$00,$00,$00,$00,$E0,$00,$1F,$1F,$18,$18,$18,$18,$1F
  .byte $80,$80,$80,$80,$80,$80,$80,$00,$01,$01,$01,$01,$01,$01,$01,$00,$00,$F8,$F8,$80,$80,$80,$80,$80,$00,$1F,$1F,$01,$01,$01,$01,$01
  .byte $80,$80,$80,$80,$80,$E0,$E0,$00,$01,$01,$01,$01,$01,$07,$07,$00,$00,$E0,$E0,$80,$80,$80,$80,$80,$00,$07,$07,$01,$01,$01,$01,$01
  .byte $00,$00,$00,$00,$00,$F8,$F8,$00,$18,$18,$18,$18,$18,$1F,$1F,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$18,$18,$18,$18,$18,$18,$18
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$3C,$7E,$DF,$FF,$FF,$FF,$7E,$3C,$3C,$42,$81,$81,$81,$81,$42,$3C,$82,$C6,$FE,$AA,$FE,$7C,$38,$00
  .byte $3C,$42,$A5,$81,$AB,$D5,$42,$3C,$3C,$42,$A5,$81,$99,$A5,$42,$3C,$3C,$42,$A5,$81,$81,$BD,$42,$3C,$3C,$42,$A5,$81,$A5,$99,$42,$3C
  .byte $00,$FF,$C3,$A5,$99,$81,$FF,$00,$10,$10,$38,$7C,$6C,$5C,$38,$00,$10,$20,$6C,$FE,$FE,$FE,$7C,$28,$00,$FF,$FF,$FF,$FF,$FF,$00,$FF
  .byte $00,$FE,$FE,$FE,$FE,$FE,$00,$FF,$00,$FC,$FC,$FC,$FC,$FC,$00,$FF,$00,$F8,$F8,$F8,$F8,$F8,$00,$FF,$00,$F0,$F0,$F0,$F0,$F0,$00,$FF
  .byte $00,$E0,$E0,$E0,$E0,$E0,$00,$FF,$00,$C0,$C0,$C0,$C0,$C0,$00,$FF,$00,$80,$80,$80,$80,$80,$00,$FF,$00,$00,$00,$00,$00,$00,$00,$FF
  .byte $00,$FF,$FF,$FF,$FF,$FF,$00,$FF,$00,$FE,$FE,$FE,$FE,$FE,$00,$FF,$00,$FC,$FC,$FC,$FC,$FC,$00,$FF,$00,$F8,$F8,$F8,$F8,$F8,$00,$FF
  .byte $00,$F0,$F0,$F0,$F0,$F0,$00,$FF,$00,$E0,$E0,$E0,$E0,$E0,$00,$FF,$00,$C0,$C0,$C0,$C0,$C0,$00,$FF,$00,$80,$80,$80,$80,$80,$00,$FF
  .byte $00,$00,$00,$00,$00,$00,$00,$FF
TCSH:
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$A1,$A1,$B1,$B1,$B1,$B1,$B1,$B1,$A1,$A1,$A1,$A1,$A1,$A1,$81,$81,$81,$81,$A1,$A1,$A1,$A1,$81,$81,$81,$81
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$A1,$A1,$B1,$B1,$B1,$B1,$B1,$B1,$A1,$A1,$A1,$A1,$A1,$A1,$81,$81,$81,$81,$B1,$B1,$B1,$B1,$B1,$B1,$A1,$A1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$A1,$A1,$A1,$A1,$A1,$A1,$81,$81,$81,$81,$A1,$A1,$A1,$A1,$81,$81,$81,$81,$B1,$B1,$B1,$B1,$B1,$B1,$A1,$A1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$A1,$A1,$A1,$A1,$A1,$A1,$81,$81,$81,$81,$A1,$A1,$A1,$A1,$81,$81,$81,$81,$B1,$B1,$B1,$B1,$B1,$B1,$A1,$A1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$A1,$A1,$A1,$A1,$A1,$A1,$81,$81,$81,$81,$A1,$A1,$A1,$A1,$81,$81,$81,$81,$B1,$B1,$B1,$B1,$B1,$B1,$A1,$A1
  .byte $A1,$A1,$A1,$A1,$81,$81,$81,$81,$A1,$A1,$A1,$A1,$81,$81,$81,$81,$B1,$B1,$B1,$B1,$B1,$B1,$A1,$A1,$B1,$B1,$B1,$B1,$B1,$B1,$A1,$A1
  .byte $A1,$A1,$A1,$A1,$81,$81,$81,$81,$A1,$A1,$A1,$A1,$81,$81,$81,$81,$B1,$B1,$B1,$B1,$B1,$B1,$A1,$A1,$B1,$B1,$B1,$B1,$B1,$B1,$A1,$A1
  .byte $A1,$A1,$A1,$A1,$81,$81,$81,$81,$A1,$A1,$A1,$A1,$81,$81,$81,$81,$B1,$B1,$B1,$B1,$B1,$B1,$A1,$A1,$B1,$B1,$B1,$B1,$B1,$B1,$A1,$A1
  .byte $A1,$A1,$A1,$A1,$81,$81,$81,$81,$A1,$A1,$A1,$A1,$81,$81,$81,$81,$B1,$B1,$B1,$B1,$B1,$B1,$A1,$A1,$B1,$B1,$B1,$B1,$B1,$B1,$A1,$A1
  .byte $BB,$BB,$BB,$BB,$BB,$BB,$BB,$BB,$81,$81,$81,$81,$81,$81,$81,$81,$61,$61,$61,$61,$61,$61,$61,$61,$E1,$E1,$E1,$E1,$E1,$E1,$E1,$E1
  .byte $31,$31,$31,$31,$31,$31,$31,$31,$51,$51,$51,$51,$51,$51,$51,$51,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1,$71,$71,$71,$71,$71,$71,$71,$71,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$81,$E1
  .byte $81,$81,$81,$81,$81,$81,$81,$E1,$81,$81,$81,$81,$81,$81,$81,$E1,$81,$81,$81,$81,$81,$81,$81,$E1,$81,$81,$81,$81,$81,$81,$81,$E1
  .byte $81,$81,$81,$81,$81,$81,$81,$E1,$81,$81,$81,$81,$81,$81,$81,$E1,$81,$81,$81,$81,$81,$81,$81,$E1,$81,$81,$81,$81,$81,$81,$81,$E1
  .byte $31,$31,$31,$31,$31,$31,$31,$E1,$31,$31,$31,$31,$31,$31,$31,$E1,$31,$31,$31,$31,$31,$31,$31,$E1,$31,$31,$31,$31,$31,$31,$31,$E1
  .byte $31,$31,$31,$31,$31,$31,$31,$E1,$31,$31,$31,$31,$31,$31,$31,$E1,$31,$31,$31,$31,$31,$31,$31,$E1,$31,$31,$31,$31,$31,$31,$31,$E1
  .byte $31,$31,$31,$31,$31,$31,$31,$E1

; the house: rows 1-19 of the name table
HOUSE_NT:
  .byte $01,$02,$03,$04,$05,$06,$07,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$08,$06,$09,$0A,$03,$0B,$01
  .byte $03,$0C,$0D,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$0E,$0F,$03
  .byte $10,$01,$11,$12,$13,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$11,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$14,$11,$03,$03
  .byte $15,$03,$11,$12,$13,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$11,$14,$16,$17,$18,$19,$14,$14,$14,$14,$14,$14,$11,$1A,$1B
  .byte $15,$03,$11,$12,$13,$12,$12,$12,$12,$12,$12,$1C,$12,$12,$12,$1D,$12,$1E,$14,$1F,$1F,$1F,$1F,$14,$14,$14,$60,$61,$14,$11,$03,$62
  .byte $15,$03,$11,$12,$13,$12,$12,$12,$12,$63,$64,$65,$66,$67,$68,$69,$12,$6A,$14,$6B,$6C,$6C,$6D,$14,$14,$14,$6E,$6F,$14,$11,$03,$62
  .byte $15,$03,$70,$71,$72,$70,$71,$73,$70,$71,$73,$70,$71,$73,$70,$71,$73,$70,$71,$73,$70,$71,$73,$70,$71,$73,$70,$71,$73,$70,$03,$62
  .byte $01,$02,$03,$04,$05,$04,$04,$04,$04,$04,$04,$04,$04,$04,$06,$07,$04,$03,$08,$08,$08,$08,$08,$09,$0A,$08,$08,$08,$08,$03,$0B,$0C
  .byte $0D,$02,$03,$04,$05,$04,$04,$04,$04,$04,$04,$04,$04,$04,$0E,$0F,$04,$03,$08,$08,$08,$08,$08,$10,$10,$08,$08,$08,$08,$03,$02,$11
  .byte $02,$02,$03,$04,$05,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$12,$08,$08,$13,$14,$15,$08,$08,$16,$17,$08,$08,$03,$02,$11
  .byte $02,$02,$03,$04,$05,$04,$04,$04,$18,$19,$19,$19,$1A,$04,$1B,$1C,$04,$1D,$1E,$08,$1F,$08,$60,$1E,$60,$08,$08,$1F,$08,$03,$02,$11
  .byte $61,$62,$63,$64,$65,$63,$64,$66,$63,$64,$66,$63,$64,$66,$63,$64,$66,$63,$64,$66,$63,$64,$66,$63,$64,$66,$63,$64,$66,$63,$02,$11
  .byte $02,$01,$03,$67,$68,$67,$69,$6A,$67,$6B,$6C,$67,$67,$67,$67,$67,$67,$03,$6D,$6D,$6D,$6D,$6D,$6D,$6D,$6D,$6E,$6F,$70,$03,$02,$71
  .byte $02,$01,$03,$67,$68,$67,$72,$73,$67,$67,$67,$67,$67,$67,$67,$67,$67,$03,$6D,$6D,$6D,$6D,$6D,$6D,$6D,$6D,$74,$75,$76,$03,$02,$77
  .byte $78,$79,$03,$67,$68,$67,$69,$69,$67,$7A,$7A,$67,$67,$67,$67,$67,$67,$12,$7B,$02,$02,$7C,$6D,$7D,$7E,$6D,$7F,$80,$81,$82,$02,$01
  .byte $01,$02,$03,$04,$05,$04,$06,$07,$04,$08,$09,$04,$0A,$0B,$0C,$0D,$04,$0E,$0F,$10,$10,$11,$12,$13,$14,$12,$15,$16,$17,$18,$19,$1A
  .byte $1B,$1A,$1C,$1D,$1E,$1C,$1D,$1E,$1C,$1D,$1E,$1C,$1D,$1E,$1C,$1D,$1E,$1C,$1D,$1E,$1C,$1D,$1E,$1C,$1D,$1E,$1C,$1D,$1E,$1C,$1B,$1A
  .byte $1B,$1F,$60,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$62,$63,$64,$65,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$61,$1B,$1A
  .byte $1B,$1B,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$66,$1B,$67

; the objects that change: row, column, width, height, states, tiles (state after state, row by row)
O_WIN1 = 0
O_WIN2 = 1
O_WIN3 = 2
O_WIN4 = 3
O_STOVE = 4
O_PC = 5
O_REC = 6
O_BATH = 7
O_VASE = 8
O_MAIL = 9
O_BOWL = 10
O_CLOCK = 11
O_TYPE = 12
NOBJ = 13
OBJ_ROW:
  .byte 3,3,13,8,15,9,15,10,15,16,16,5,9
OBJ_COL:
  .byte 7,23,11,19,9,20,23,8,14,30,5,9,25
OBJ_W:
  .byte 2,2,2,2,2,3,2,5,1,1,1,2,2
OBJ_H:
  .byte 2,2,2,2,1,1,1,1,1,1,1,1,1
OBJ_N:
  .byte 4,4,4,4,2,3,2,5,1,1,1,2,2
OBJ_S:
  .byte 2,2,2,2,3,3,3,3,3,2,2,3,3
OBJ_TLO:
  .byte <OT_O_WIN1,<OT_O_WIN2,<OT_O_WIN3,<OT_O_WIN4,<OT_O_STOVE,<OT_O_PC,<OT_O_REC,<OT_O_BATH,<OT_O_VASE,<OT_O_MAIL,<OT_O_BOWL,<OT_O_CLOCK,<OT_O_TYPE
OBJ_THI:
  .byte >OT_O_WIN1,>OT_O_WIN2,>OT_O_WIN3,>OT_O_WIN4,>OT_O_STOVE,>OT_O_PC,>OT_O_REC,>OT_O_BATH,>OT_O_VASE,>OT_O_MAIL,>OT_O_BOWL,>OT_O_CLOCK,>OT_O_TYPE
OT_O_WIN1:
  .byte $74,$74,$74,$74,$75,$76,$77,$78
OT_O_WIN2:
  .byte $74,$74,$74,$74,$75,$76,$77,$78
OT_O_WIN3:
  .byte $83,$83,$83,$83,$84,$85,$86,$87
OT_O_WIN4:
  .byte $83,$83,$83,$83,$84,$85,$86,$87
OT_O_STOVE:
  .byte $7A,$7A,$88,$88,$89,$89
OT_O_PC:
  .byte $8A,$8A,$8A,$8B,$8C,$8D,$8E,$8F,$90
OT_O_REC:
  .byte $91,$92,$93,$92,$94,$92
OT_O_BATH:
  .byte $04,$04,$04,$04,$04,$95,$96,$96,$96,$96,$97,$98,$98,$98,$98
OT_O_VASE:
  .byte $67,$99,$9A
OT_O_MAIL:
  .byte $19,$68
OT_O_BOWL:
  .byte $69,$6A
OT_O_CLOCK:
  .byte $79,$12,$7A,$12,$7B,$12
OT_O_TYPE:
  .byte $08,$08,$9B,$9C,$9D,$9E

; panel tiles
BAR_T:
  .byte 255,254,253,252,251,250,249,248,247
BARLOW_T:
  .byte 246,245,244,243,242,241,240,239,238
T_FOOD = 237
T_WATER = 236
T_MAIL = 235
T_HAPPY = 234
T_FINE = 233
T_SAD = 232
T_SICK = 231
T_CAT = 230
T_LEDOFF = 229
T_LEDON = 228
T_PAPER = 227

; title
TXT_BIG:
  .byte 2,10,226,225,222,221,218,217,218,217,226,225,214,213,0
  .byte 3,10,224,223,220,219,216,215,216,215,224,223,212,211,0
  .byte 4,8,210,213,207,206,203,202,199,198,32,32,196,195,226,226,192,191,0
  .byte 5,8,209,208,205,204,201,200,197,211,32,32,194,193,194,204,216,215,0
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
  .byte <SG0_0,<SG0_1,<SG0_2,<SG0_3,<SG1_0,<SG1_1,<SG1_2,<SG1_3,<SG2_0,<SG2_1,<SG2_2,<SG2_3,<SG3_0,<SG3_1,<SG3_2,<SG3_3,<SG4_0,<SG4_1,<SG4_2,<SG4_3,<SG5_0,<SG5_1,<SG5_2,<SG5_3
SONGP_HI:
  .byte >SG0_0,>SG0_1,>SG0_2,>SG0_3,>SG1_0,>SG1_1,>SG1_2,>SG1_3,>SG2_0,>SG2_1,>SG2_2,>SG2_3,>SG3_0,>SG3_1,>SG3_2,>SG3_3,>SG4_0,>SG4_1,>SG4_2,>SG4_3,>SG5_0,>SG5_1,>SG5_2,>SG5_3
SG0_0:
  .byte $25,$08,$2A,$08,$2E,$08,$2C,$08,$2A,$08,$29,$08,$2A,$10,$25,$08,$27,$08,$29,$08,$2A,$08,$2C,$08,$2E,$08,$2C,$18,$00,$08,$2E,$08
  .byte $31,$08,$2E,$08,$2C,$08,$2A,$08,$27,$08,$29,$08,$2C,$08,$29,$08,$2A,$18,$00,$08,$FF
SG0_1:
  .byte $22,$18,$25,$18,$22,$18,$23,$18,$25,$18,$25,$18,$1E,$18,$1D,$18,$25,$18,$22,$18,$FF
SG0_2:
  .byte $12,$18,$12,$18,$12,$18,$0B,$18,$0D,$18,$0D,$18,$12,$18,$0D,$18,$0D,$18,$12,$18,$FF
SG0_3:
  .byte $01,$08,$03,$08,$03,$08,$01,$08,$03,$08,$03,$08,$01,$08,$03,$08,$03,$08,$01,$08,$03,$08,$03,$08,$01,$08,$03,$08,$03,$08,$01,$08
  .byte $03,$08,$03,$08,$01,$08,$03,$08,$03,$08,$01,$08,$03,$08,$03,$08,$01,$08,$03,$08,$03,$08,$01,$08,$03,$08,$03,$08,$FF
SG1_0:
  .byte $29,$06,$29,$06,$2C,$06,$29,$06,$27,$06,$25,$06,$27,$0C,$29,$06,$2C,$06,$2E,$06,$2C,$06,$29,$0C,$00,$0C,$29,$06,$29,$06,$2C,$06
  .byte $2E,$06,$31,$06,$2E,$06,$2C,$0C,$29,$06,$27,$06,$25,$06,$27,$06,$25,$18,$FF
SG1_1:
  .byte $19,$18,$19,$18,$14,$18,$19,$18,$19,$18,$1E,$18,$14,$18,$19,$18,$FF
SG1_2:
  .byte $0D,$0C,$08,$0C,$0D,$0C,$08,$0C,$0A,$0C,$05,$0C,$0D,$0C,$08,$0C,$0D,$0C,$08,$0C,$06,$0C,$0A,$0C,$08,$0C,$08,$0C,$0D,$18,$FF
SG1_3:
  .byte $01,$0C,$02,$0C,$01,$0C,$02,$0C,$01,$0C,$02,$0C,$01,$0C,$02,$0C,$01,$0C,$02,$0C,$01,$0C,$02,$0C,$01,$0C,$02,$0C,$04,$18,$FF
SG2_0:
  .byte $27,$0C,$27,$0C,$23,$09,$25,$03,$27,$0C,$20,$0C,$22,$09,$23,$03,$25,$0C,$22,$0C,$27,$0C,$2A,$09,$28,$03,$27,$0C,$25,$0C,$23,$09
  .byte $22,$03,$20,$0C,$1B,$18,$2C,$0C,$2C,$09,$2A,$03,$28,$0C,$27,$0C,$25,$0C,$28,$09,$27,$03,$25,$0C,$23,$0C,$22,$0C,$23,$09,$25,$03
  .byte $27,$0C,$1F,$0C,$20,$24,$00,$0C,$FF
SG2_1:
  .byte $23,$18,$23,$18,$1C,$18,$1C,$18,$1E,$18,$1E,$18,$1B,$18,$1B,$18,$23,$18,$23,$18,$20,$18,$20,$18,$1F,$18,$1F,$18,$1B,$18,$00,$18
  .byte $FF
SG2_2:
  .byte $08,$0C,$0F,$0C,$08,$0C,$0F,$0C,$0D,$0C,$08,$0C,$0D,$0C,$08,$0C,$0B,$0C,$06,$0C,$0B,$0C,$06,$0C,$0F,$0C,$0A,$0C,$0F,$0C,$03,$0C
  .byte $10,$0C,$0B,$0C,$10,$0C,$0B,$0C,$0D,$0C,$08,$0C,$0D,$0C,$08,$0C,$0F,$0C,$0A,$0C,$0F,$0C,$07,$0C,$08,$0C,$03,$0C,$08,$18,$FF
SG2_3:
  .byte $01,$0C,$02,$09,$02,$03,$01,$0C,$02,$0C,$01,$0C,$02,$09,$02,$03,$01,$0C,$02,$0C,$01,$0C,$02,$09,$02,$03,$01,$0C,$02,$0C,$01,$0C
  .byte $02,$09,$02,$03,$01,$0C,$02,$0C,$01,$0C,$02,$09,$02,$03,$01,$0C,$02,$0C,$01,$0C,$02,$09,$02,$03,$01,$0C,$02,$0C,$01,$0C,$02,$09
  .byte $02,$03,$01,$0C,$02,$0C,$01,$0C,$02,$0C,$04,$18,$FF
SG3_0:
  .byte $29,$06,$2C,$06,$30,$0C,$2E,$06,$2C,$06,$2B,$0C,$29,$06,$2B,$06,$2C,$0C,$27,$0C,$24,$0C,$25,$06,$27,$06,$29,$0C,$2C,$06,$2B,$06
  .byte $29,$0C,$27,$06,$29,$06,$2B,$0C,$24,$18,$29,$06,$2C,$06,$30,$0C,$31,$06,$30,$06,$2E,$0C,$2C,$06,$2E,$06,$30,$0C,$33,$0C,$30,$0C
  .byte $31,$0C,$30,$0C,$2E,$0C,$2B,$0C,$29,$24,$00,$0C,$FF
SG3_1:
  .byte $24,$18,$24,$18,$24,$18,$22,$18,$20,$18,$20,$18,$1F,$18,$1F,$18,$20,$18,$22,$18,$20,$18,$20,$18,$1D,$18,$1C,$18,$1D,$18,$00,$18
  .byte $FF
SG3_2:
  .byte $05,$06,$11,$06,$05,$06,$11,$06,$05,$06,$11,$06,$05,$06,$11,$06,$08,$06,$14,$06,$08,$06,$14,$06,$03,$06,$0F,$06,$03,$06,$0F,$06
  .byte $01,$06,$0D,$06,$01,$06,$0D,$06,$01,$06,$0D,$06,$01,$06,$0D,$06,$03,$06,$0F,$06,$03,$06,$0F,$06,$0C,$06,$18,$06,$0C,$06,$18,$06
  .byte $05,$06,$11,$06,$05,$06,$11,$06,$0A,$06,$16,$06,$0A,$06,$16,$06,$08,$06,$14,$06,$08,$06,$14,$06,$08,$06,$14,$06,$08,$06,$14,$06
  .byte $0A,$06,$16,$06,$0A,$06,$16,$06,$0C,$06,$18,$06,$0C,$06,$18,$06,$05,$06,$11,$06,$05,$06,$11,$06,$05,$06,$11,$06,$05,$06,$11,$06
  .byte $FF
SG3_3:
  .byte $01,$0C,$02,$0C,$01,$06,$01,$06,$02,$0C,$01,$0C,$02,$0C,$01,$06,$01,$06,$02,$0C,$01,$0C,$02,$0C,$01,$06,$01,$06,$02,$0C,$01,$0C
  .byte $02,$0C,$01,$06,$01,$06,$02,$0C,$01,$0C,$02,$0C,$01,$06,$01,$06,$02,$0C,$01,$0C,$02,$0C,$01,$06,$01,$06,$02,$0C,$01,$0C,$02,$0C
  .byte $01,$06,$01,$06,$02,$0C,$01,$0C,$02,$0C,$04,$18,$FF
SG4_0:
  .byte $25,$06,$00,$03,$29,$03,$2C,$06,$31,$06,$30,$06,$2C,$06,$29,$0C,$2A,$06,$2E,$06,$2C,$06,$29,$06,$27,$0C,$00,$0C,$27,$06,$00,$03
  .byte $2A,$03,$2E,$06,$33,$06,$31,$06,$2E,$06,$2A,$0C,$2C,$06,$2A,$06,$29,$06,$27,$06,$25,$0C,$00,$0C,$29,$06,$29,$06,$2A,$06,$2C,$06
  .byte $2E,$0C,$2C,$0C,$2A,$06,$2A,$06,$29,$06,$27,$06,$29,$0C,$25,$0C,$27,$06,$29,$06,$2A,$06,$27,$06,$2C,$06,$2A,$06,$29,$06,$27,$06
  .byte $25,$0C,$20,$06,$25,$06,$31,$0C,$00,$0C,$FF
SG4_1:
  .byte $1D,$18,$1D,$18,$22,$18,$20,$18,$1E,$18,$1E,$18,$1E,$18,$1D,$18,$1D,$18,$1D,$18,$22,$18,$20,$18,$1E,$18,$1E,$18,$1D,$18,$00,$18
  .byte $FF
SG4_2:
  .byte $0D,$0C,$08,$0C,$0D,$0C,$08,$0C,$06,$0C,$0D,$0C,$0D,$0C,$08,$0C,$0F,$0C,$0A,$0C,$0F,$0C,$0A,$0C,$08,$0C,$0F,$0C,$0D,$0C,$08,$0C
  .byte $0D,$0C,$08,$0C,$0A,$0C,$05,$0C,$06,$0C,$0D,$0C,$0D,$0C,$08,$0C,$08,$0C,$0F,$0C,$08,$0C,$0C,$0C,$0D,$0C,$08,$0C,$0D,$18,$FF
SG4_3:
  .byte $01,$0C,$03,$0C,$02,$0C,$03,$0C,$01,$0C,$03,$0C,$02,$0C,$03,$0C,$01,$0C,$03,$0C,$02,$0C,$03,$0C,$01,$0C,$03,$0C,$02,$0C,$03,$0C
  .byte $01,$0C,$03,$0C,$02,$0C,$03,$0C,$01,$0C,$03,$0C,$02,$0C,$03,$0C,$01,$0C,$03,$0C,$02,$0C,$03,$0C,$01,$0C,$03,$0C,$04,$18,$FF
SG5_0:
  .byte $2A,$06,$2E,$06,$31,$06,$2E,$06,$2F,$06,$2C,$06,$2A,$12,$FF
SG5_1:
  .byte $22,$12,$23,$12,$22,$12,$FF
SG5_2:
  .byte $12,$12,$0D,$12,$12,$12,$FF
SG5_3:
  .byte $01,$06,$03,$06,$03,$06,$01,$06,$03,$06,$03,$06,$04,$12,$FF

; one-shot tone effects: period and volume for every frame
WH_TL:
  .byte $00,$5B,$BE,$95,$D0,$B6,$A0,$8B,$77,$65,$53,$43,$33,$24,$16,$09,$FC,$F0,$E4,$E1,$F0,$00,$12,$24,$38,$4E,$65,$7E,$99,$19,$1E,$19
  .byte $1E,$19,$1E,$19,$1E,$19,$1E,$19,$1E,$19,$1E,$19,$1E,$19,$1E,$15,$2A,$18,$18,$18,$18,$18,$18,$18,$18,$18,$18,$18,$18,$18,$18,$F0
  .byte $F0,$00,$00,$00,$00,$00,$04,$04,$3C,$3C,$3C,$2F,$2F,$2F,$28,$28,$28,$1E,$1E,$1E,$1E,$1E,$1E,$78,$7B,$7E,$82,$85,$89,$8D,$92,$96
  .byte $9B,$A0,$A5,$AB,$B2,$B8,$C0,$C8,$D0,$2F,$2F,$2F,$2F,$2F,$2F,$2F,$2F,$2F,$2F,$2F,$2F,$3C,$3C,$3C,$3C,$3C,$3C,$3C,$3C,$3C,$3C,$3C
  .byte $3C,$3C,$3C,$3C,$3C,$3C,$3C,$24,$24,$2F,$2F,$2F,$24,$24,$24,$24,$24,$BD,$BD,$BD,$BD,$BD,$BD,$EF,$EF,$EF,$EF,$EF,$EF,$EF,$EF,$EF
  .byte $EF,$28,$28,$28,$28,$78,$78,$78,$78,$3C,$3C,$3C,$3C,$2F,$2F,$2F,$2F,$28,$28,$28,$28,$1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E,$9F
  .byte $9F,$9F,$9F,$9F,$9F,$A9,$A9,$A9,$A9,$A9,$A9,$B3,$B3,$B3,$B3,$B3,$B3,$BD,$BD,$BD,$BD,$BD,$BD,$BD,$BD,$BD,$BD,$BD,$BD,$1F,$1F,$34
  .byte $34,$45,$51,$60,$77,$9C,$10,$12,$15,$19,$68,$59,$4E,$45,$45,$4A,$50,$56,$5D,$66,$70,$7D
WH_TH:
  .byte $00,$01,$01,$00,$00,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$01,$01,$01,$01,$01,$02,$02,$02,$02,$02,$02,$02,$02,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$01,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
WH_VOL:
  .byte $00,$06,$04,$06,$04,$03,$03,$03,$03,$04,$04,$04,$04,$05,$05,$05,$05,$06,$06,$06,$06,$05,$05,$04,$04,$03,$03,$02,$02,$0B,$0B,$0B
  .byte $0B,$00,$00,$0B,$0B,$0B,$0B,$00,$00,$0B,$0B,$0B,$0B,$00,$00,$09,$05,$0C,$0B,$0A,$0A,$09,$08,$07,$07,$06,$05,$04,$04,$03,$02,$0D
  .byte $09,$00,$00,$00,$00,$00,$0D,$09,$0A,$09,$08,$0A,$09,$08,$0A,$09,$08,$0A,$09,$08,$06,$05,$04,$09,$09,$08,$08,$07,$07,$07,$06,$06
  .byte $05,$05,$04,$04,$04,$03,$03,$02,$02,$0C,$0C,$0B,$0B,$0A,$0A,$09,$09,$08,$08,$07,$07,$0C,$0B,$0B,$0A,$0A,$09,$09,$08,$08,$07,$07
  .byte $06,$06,$05,$05,$04,$04,$03,$08,$06,$0A,$0A,$09,$0A,$09,$08,$07,$06,$0B,$0B,$0A,$0A,$09,$09,$0B,$0A,$0A,$09,$08,$08,$07,$06,$06
  .byte $05,$0A,$09,$08,$07,$0A,$09,$08,$07,$0C,$0B,$0B,$0A,$0C,$0B,$0B,$0A,$0C,$0B,$0B,$0A,$0C,$0B,$0A,$09,$08,$08,$07,$06,$05,$04,$0B
  .byte $0B,$0A,$0A,$09,$09,$0B,$0B,$0A,$0A,$09,$09,$0B,$0B,$0A,$0A,$09,$09,$0B,$0A,$0A,$09,$08,$07,$07,$06,$05,$04,$04,$03,$07,$07,$06
  .byte $06,$0A,$09,$07,$06,$04,$03,$02,$02,$01,$07,$08,$09,$0A,$0A,$09,$08,$07,$06,$05,$04,$03
WH_START:
  .byte $00,$01,$03,$05,$1D,$2F,$31,$3F,$48,$57,$69,$87,$89,$91,$A1,$A5,$A9,$BF,$DD,$E1,$E6,$EA
WH_LEN:
  .byte $00,$02,$02,$18,$12,$02,$0E,$09,$0F,$12,$1E,$02,$08,$10,$04,$04,$16,$1E,$04,$05,$04,$0C
W_STEP = 1
W_RUNG = 2
W_SNORE = 3
W_RING = 4
W_TYPE = 5
W_BELL = 6
W_KNOCK = 7
W_HAPPY = 8
W_SIGH = 9
W_DING = 10
W_MENU = 11
W_OK = 12
W_NO = 13
W_BIT1 = 14
W_BIT0 = 15
W_WIN = 16
W_LOSE = 17
W_BEEP = 18
W_BOUNCE = 19
W_PAGE = 20
W_MEOW = 21

; noise effects: noise volume / period, low tone volume / period for every frame
EX_NV:
  .byte $00,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$02,$02,$02,$02,$06,$05,$05,$06,$05,$05,$06,$05,$05,$06,$05
  .byte $05,$06,$05,$05,$06,$05,$05,$06,$05,$05,$06,$05,$05,$06,$05,$05,$06,$05,$05,$09,$06,$03,$03,$03,$03,$03,$01,$01,$01,$01,$08,$05
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00
EX_NP:
  .byte $00,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06
  .byte $06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$0C,$0E,$10,$14,$14,$14,$14,$14,$14,$14,$14,$0A,$0C
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00
EX_VC:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$0A,$07,$04,$00,$00,$00,$00,$00,$00,$00,$00,$09,$07
  .byte $04,$04,$04,$04,$04,$04,$04,$04,$04,$04
EX_TL:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$39,$5B,$87,$00,$00,$00,$00,$00,$00,$00,$00,$09,$38
  .byte $12,$12,$12,$12,$12,$12,$12,$12,$12,$12
EX_TH:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$01,$01,$00,$00,$00,$00,$00,$00,$00,$00,$02,$02
  .byte $04,$04,$04,$04,$04,$04,$04,$04,$04,$04
EX_START:
  .byte $00,$01,$15,$33,$36,$3E
EX_LEN:
  .byte $00,$14,$1E,$03,$08,$0C
S_SIZZLE = 1
S_SPLASH = 2
S_TOK = 3
S_PEDAL = 4
S_FRDOOR = 5

GFX_LOAD:
  .byte 1, $00,$41, <512,>512, <FONT,>FONT
  .byte 2, $00,$61, <512,>512, $F1,0
  .byte 1, $08,$40, <248,>248, <TP0A,>TP0A
  .byte 1, $08,$60, <248,>248, <TC0A,>TC0A
  .byte 1, $00,$43, <224,>224, <TP0B,>TP0B
  .byte 1, $00,$63, <224,>224, <TC0B,>TC0B
  .byte 1, $F8,$45, <520,>520, <TPSH,>TPSH
  .byte 1, $F8,$65, <520,>520, <TCSH,>TCSH
  .byte 2, $00,$60, <8,>8, $11,0
  .byte 1, $00,$49, <512,>512, <FONT,>FONT
  .byte 2, $00,$69, <512,>512, $F1,0
  .byte 1, $08,$48, <248,>248, <TP1A,>TP1A
  .byte 1, $08,$68, <248,>248, <TC1A,>TC1A
  .byte 1, $00,$4B, <504,>504, <TP1B,>TP1B
  .byte 1, $00,$6B, <504,>504, <TC1B,>TC1B
  .byte 1, $F8,$4D, <520,>520, <TPSH,>TPSH
  .byte 1, $F8,$6D, <520,>520, <TCSH,>TCSH
  .byte 2, $00,$68, <8,>8, $11,0
  .byte 1, $00,$51, <512,>512, <FONT,>FONT
  .byte 2, $00,$71, <512,>512, $F1,0
  .byte 1, $08,$50, <248,>248, <TP2A,>TP2A
  .byte 1, $08,$70, <248,>248, <TC2A,>TC2A
  .byte 1, $00,$53, <88,>88, <TP2B,>TP2B
  .byte 1, $00,$73, <88,>88, <TC2B,>TC2B
  .byte 1, $F8,$55, <520,>520, <TPSH,>TPSH
  .byte 1, $F8,$75, <520,>520, <TCSH,>TCSH
  .byte 2, $00,$70, <8,>8, $11,0
  .byte 2, $00,$78, <768,>768, $20,0
  .byte 0
