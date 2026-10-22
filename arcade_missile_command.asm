;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;                                                              ;
;   ARCADE_MISSILE_COMMAND  -  difendi le citta' dai missili   ;
;   65C02 assembly, TMS9918A Graphics II (bitmap 256x192)      ;
;   Base: 1vs1 / tank (NMI + trampolino $0FD0, joystick VIA)   ;
;                                                              ;
;   - P1 su PORTA $D581, P2 su PORTB $D580 (si unisce premendo ;
;     un tasto del suo joystick); i due mirini giocano insieme ;
;   - joystick = muove il mirino                               ;
;       tasto 1 (bit4) = spara dalla base piu' vicina al mirino;
;       tasto 2 (bit5) = spara dalla base centrale (piu' veloce)
;   - 6 citta' e 3 basi con 10 missili ciascuna                ;
;   - schermo = bitmap: scie, esplosioni e testi sono disegnati;
;     pixel per pixel; una copia dello schermo e' in RAM       ;
;     ($4000 pattern, $6000 colori) per ridisegnare le celle   ;
;   - SONORO (2 x AY-3-8910, motore di tank_sound.asm): breve  ;
;     musica al titolo, fischi diversi per i missili, esplosio-;
;     ni piccole e grandi, musica di sconfitta; tutto suonato  ;
;     dall'NMI (SND_TICK), il main loop lascia solo richieste  ;
;   - il main loop scrive sul VDP solo con l'interrupt spento  ;
;     (VDP_INT_OFF subito dopo l'NMI); l'NMI aggiorna solo la  ;
;     SAT (i mirini) durante il vblank                         ;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; ---------------- zero page ----------------
FRAME_CNT   = $60
LAST_FRAME  = $61
RND         = $62
VINT        = $63      ; 1 = interrupt VDP acceso
T0          = $64
T1          = $65
T2          = $66
T3          = $67
T4          = $68
T5          = $69
T6          = $6A
T7          = $6B
PTR         = $6C      ; 2 byte
PTR2        = $6E      ; 2 byte: puntatore ai colori della cella (shadow)
SPTR        = $70      ; 2 byte: puntatore al pattern della cella (shadow)
TP          = $72      ; 2 byte: record dei testi
ECP         = $74      ; 2 byte: forma esplosione, cella corrente
ESH         = $76      ; 2 byte: forma esplosione, inizio
CELLC       = $78      ; colonna cella (0-31)
CELLR       = $79      ; riga cella (0-23)
TCOL        = $7A      ; byte colore (fg<<4 | bg) per i testi
PX          = $7B      ; pixel da disegnare
PY          = $7C
PCOL        = $7D
LX0         = $7E      ; linea: partenza e arrivo
LY0         = $7F
LX1         = $80
LY1         = $81
EXX         = $82      ; centro nuova esplosione
EXY         = $83
NSTEP       = $84
NACT_EN     = $85      ; testate nemiche in volo
SLOTV       = $86
MCNT        = $87
SHAPEV      = $88
FCOL        = $89
EC0         = $8A
ER0         = $8B
EI          = $8C
ESTEP       = $8D
BUDGET      = $8E
P_JOY       = $8F      ; 2 byte (joystick, 1 = premuto)
P_OLD       = $91      ; 2 byte
P_CX        = $93      ; 2 byte: mirino X
P_CY        = $95      ; 2 byte: mirino Y
P_ACT       = $97      ; 2 byte: mirino attivo
FBTN        = $99
CURI        = $9A
SCORE       = $9B      ; 3 byte BCD (basso, medio, alto)
HISCORE     = $9E      ; 3 byte BCD
WAVE        = $A1
WAVE_BCD    = $A2
HUD_DIRTY   = $A3
AM_DIRTY    = $A4
SPAWN_LEFT  = $A5
SPAWN_TMR   = $A6
SPAWN_DLY   = $A7
MAX_ACT     = $A8
EN_SPF      = $A9
NEXTB       = $AA      ; prossima soglia citta' extra (BCD, decine di migliaia)
GO_TMR      = $AB
NCITY       = $AC
ADLO        = $AD
ADMID       = $AE
B_LO        = $AF
B_MID       = $B0
SITE_C0       = $B1
SITE_W          = $B2
SITE_WC         = $B3
SITEV       = $B4
BIGC        = $B5
BIGR        = $B6
TYV         = $B7
AMI         = $B8
MULT        = $B9
NMIS        = $BA

; ---------------- sonoro: due AY-3-8910, clock 1 MHz ----------------
AY_R_LATCH = $D380       ; AY destro
AY_R_WRITE = $D381
AY_L_LATCH = $D384       ; AY sinistro
AY_L_WRITE = $D385

SN1        = $BB         ; temporanei del sonoro (solo NMI)
SND_T1     = $BC
SH_L       = $C0         ; shadow registri AY sinistro 0-10  (11 byte)
SH_R       = $D0         ; shadow registri AY destro   0-10  (SH_R = SH_L + 16)
TR_PL      = $DC         ; 4 tracce: puntatore (lo / hi), contatore, attiva,
TR_PH      = $E0         ;           nota, volume, eta' della nota
TR_CT      = $E4
TR_ACT     = $E8
TR_NOTE    = $EC
TR_VOL     = $F0
TR_AGE     = $F4
SND_PTR    = $F8         ; 2 byte
SND_CMD    = $FA         ; comando al motore sonoro (CMD_*), eseguito dall'NMI
SND_MODE   = $FB         ; 0 = effetti di gioco, 1 = musica
SND_BUSY   = $FC         ; 1 finche' la canzone sta suonando
SND_PH     = $FD
SND_RND    = $FE
SN0        = $FF

WH_ID      = $0700       ; fischio in corso per chip (0 = nessuno)  2 byte
WH_POS     = $0702       ; frame trascorsi
EX_ID      = $0704       ; esplosione in corso per chip (0 = nessuna, 1 piccola, 2 grande)
EX_POS     = $0706
SMT0       = $0708       ; temporanei lato main loop
SMT1       = $0709

CMD_GAME   = 1           ; silenzio + effetti di gioco
CMD_TITLE  = 2           ; musica del titolo
CMD_LOSE   = 3           ; musica di sconfitta

; ---------------- RAM (array) ----------------
NM = 24                 ; slot missili (nemici, nostri, scie in cancellazione)
NE = 8                  ; slot esplosioni
M_ST   = $0400          ; 0 libero, 1 in volo, 2 scia in cancellazione
M_TYPE = $0420          ; 0 nemico, 1 nostro
M_FLG  = $0440          ; bit0 = MIRV: si divide a quota M_SPLY
M_OX   = $0460          ; origine
M_OY   = $0480
M_X    = $04A0          ; posizione corrente
M_Y    = $04C0
M_TX   = $04E0          ; bersaglio
M_TY   = $0500
M_SX   = $0520          ; verso X ($01 / $FF)
M_SY   = $0540          ; verso Y
M_MAJ  = $0560          ; 0 = asse maggiore Y, 1 = X
M_LEN  = $0580          ; passi totali (asse maggiore)
M_MIN  = $05A0          ; asse minore
M_ERR  = $05C0          ; errore di Bresenham
M_REM  = $05E0          ; passi rimasti
M_SPF  = $0600          ; velocita': frazione
M_SPI  = $0620          ; velocita': parte intera
M_ACC  = $0640
M_TG   = $0660          ; sito bersaglio (nemici)
M_SPLY = $0680          ; quota di divisione MIRV
X_ST   = $06A0          ; esplosioni
X_CX   = $06A8
X_CY   = $06B0
X_STG  = $06B8
X_TMR  = $06C0
X_RAD  = $06C8
T_ALIVE = $06D0         ; 9 siti: 0 base,1-3 citta',4 base,5-7 citta',8 base
AMMO    = $06E0         ; 3 basi

SH_PAT = $4000          ; copia dello schermo (pattern) in RAM
SH_COL = $6000          ; copia dei colori

; ---------------- parametri ----------------
GROUND_Y    = 168       ; riga di impatto (cima di citta' e basi)
BASE_FY     = 167       ; da dove partono i nostri missili
SPAWN_Y     = 8
CUR_SPEED   = 3
CUR_XMIN    = 8
CUR_XMAX    = 247
CUR_YMIN    = 12
CUR_YMAX    = 160
BTN_MASK    = %00110000
HIDE_Y      = $C0
EXPL_HOLD   = 4         ; frame per ogni fase dell'esplosione
EXPL_BUDGET = 2         ; esplosioni ridisegnate per frame
ERASE_N     = 6         ; pixel di scia cancellati per frame
COL_ENEMY   = $91
COL_PLAYER  = $71
MISS_AMMO   = 10

PORTB_JOY = $d580       ;         |P2|P1|RG|LF|DW|UP (LSB)   joystick 2
PORTA_JOY = $d581       ;         |P2|P1|RG|LF|DW|UP (LSB)   joystick 1
DDRB_JOY  = $d582
DDRA_JOY  = $d583

VDP_SPRITE_ATT_BASE = $3B00
VDP_NAME_TABLE_BASE = $3800
VREG  = $B001           ; VDP REGISTER
VDATA = $B000           ; VDP RAM
VDP_WRITE_VRAM_BIT = %01000000
VDP_REGISTER_BITS  = %10000000


 .org $0FD0               ; trampolino chiamato da NMI_HANDLER (bios) con JSR $0FD0
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
  JSR SND_INIT                 ; AY a zero (l'interrupt VDP e' ancora spento)
  LDA #$00
  STA DDRA_JOY
  STA DDRB_JOY
  STA VINT                     ; interrupt VDP spento (R1 = $C6)
  STA HISCORE
  STA HISCORE+1
  STA HISCORE+2
  STA FRAME_CNT
  STA LAST_FRAME
  LDA #$A5
  STA RND
  JSR HIDE_SPRITES
  JMP TITLE


; ===============================================================
;  SCHERMATA START
; ===============================================================
TITLE:
  LDX #$FF
  TXS                          ; da qui non si torna indietro: stack pulito
  JSR HIDE_SPRITES
  JSR VDP_INT_OFF
  JSR CLEAR_SCREEN
  JSR DRAW_GROUND
  LDA #$01
  LDX #$00
.ti_alive:
  STA T_ALIVE,X
  INX
  CPX #9
  BNE .ti_alive
  LDX #$00
.ti_sites:
  JSR DRAW_SITE
  INX
  CPX #9
  BNE .ti_sites
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
  LDA #<TXT_REC
  STA TP
  LDA #>TXT_REC
  STA TP+1
  JSR DRAW_TEXT
  LDA #$0F
  ASL A
  ASL A
  ASL A
  ASL A
  ORA #$01
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
  JSR VDP_INT_ON
  LDA #CMD_TITLE               ; breve musica (si puo' saltare premendo un tasto)
  STA SND_CMD
  JSR WAIT_FIRE
  LDA FRAME_CNT                ; il momento in cui premi il tasto semina il caso
  ORA #$01
  STA RND
  JMP NEW_GAME


; ===============================================================
;  NUOVA PARTITA
; ===============================================================
NEW_GAME:
  LDA #CMD_GAME                ; ferma la musica, effetti di gioco
  STA SND_CMD
  LDA #$00
  STA SCORE
  STA SCORE+1
  STA SCORE+2
  STA P_ACT+1
  STA GO_TMR
  LDA #$01
  STA P_ACT
  STA WAVE
  STA WAVE_BCD
  STA NEXTB
  STA HUD_DIRTY
  STA AM_DIRTY
  LDX #$00
  LDA #$01
.ng_alive:
  STA T_ALIVE,X
  INX
  CPX #9
  BNE .ng_alive
  JSR VDP_INT_OFF
  JSR CLEAR_SCREEN
  JSR DRAW_GROUND
  LDA #<TXT_HUD
  STA TP
  LDA #>TXT_HUD
  STA TP+1
  JSR DRAW_TEXT
  JMP WAVE_START


; ===============================================================
;  INIZIO ONDATA
; ===============================================================
WAVE_START:
  LDX #$FF
  TXS
  JSR VDP_INT_OFF
  JSR CLEAR_PLAYFIELD
  ; citta' extra ogni 10000 punti (se ce n'e' una distrutta)
  LDA SCORE+2
  CMP NEXTB
  BCC .ws_nobonus
  LDX #$00
.ws_find:
  LDA T_ALIVE,X
  BEQ .ws_rebuild
  INX
  CPX #9
  BNE .ws_find
  BRA .ws_nobonus
.ws_rebuild:
  LDA #$01
  STA T_ALIVE,X
  SED
  CLC
  LDA NEXTB
  ADC #$01
  STA NEXTB
  CLD
.ws_nobonus:
  ; le basi sono sempre ricostruite, con tutti i missili
  LDA #$01
  STA T_ALIVE
  STA T_ALIVE+4
  STA T_ALIVE+8
  LDA #MISS_AMMO
  STA AMMO
  STA AMMO+1
  STA AMMO+2
  LDX #$00
.ws_sites:
  JSR DRAW_SITE
  INX
  CPX #9
  BNE .ws_sites
  ; azzera slot
  LDA #$00
  LDX #(NM-1)
.ws_cm:
  STA M_ST,X
  DEX
  BPL .ws_cm
  LDX #(NE-1)
.ws_ce:
  STA X_ST,X
  DEX
  BPL .ws_ce
  STA GO_TMR
  STA NACT_EN
  ; parametri ondata (indice = ondata-1, massimo 14)
  LDX WAVE
  DEX
  CPX #15
  BCC .ws_idx
  LDX #14
.ws_idx:
  LDA WAVE_N,X
  STA SPAWN_LEFT
  LDA WAVE_MAX,X
  STA MAX_ACT
  LDA WAVE_DLY,X
  STA SPAWN_DLY
  STA SPAWN_TMR
  LDA WAVE_SPF,X
  STA EN_SPF
  ; mirini al centro
  LDA #128
  STA P_CX
  STA P_CX+1
  LDA #96
  STA P_CY
  STA P_CY+1
  JSR READ_JOY
  LDA P_JOY
  AND #BTN_MASK
  STA P_OLD
  LDA P_JOY+1
  AND #BTN_MASK
  STA P_OLD+1
  ; messaggio "ONDATA nn"
  LDA #<TXT_WAVE
  STA TP
  LDA #>TXT_WAVE
  STA TP+1
  JSR DRAW_TEXT
  LDA #$0B
  ASL A
  ASL A
  ASL A
  ASL A
  ORA #$01
  STA TCOL
  LDA #9
  STA CELLR
  LDA #18
  STA CELLC
  LDA WAVE_BCD
  JSR PUT_BCD
  JSR DRAW_SCORE
  JSR DRAW_AMMO
  LDA #$00
  STA HUD_DIRTY
  STA AM_DIRTY
  JSR BUILD_SAT
  LDA #W_WAVE
  LDX #2
  JSR SFX_WHISTLE
  JSR VDP_INT_ON
  LDA #70
  JSR WAIT_FRAMES
  JSR VDP_INT_OFF
  JSR CLEAR_PLAYFIELD
  JSR VDP_INT_ON


; ===============================================================
;  CICLO DI GIOCO: un giro = un frame
; ===============================================================
GAME_LOOP:
  JSR VDP_INT_OFF              ; aspetta il vblank e libera il VDP
  JSR READ_JOY
  JSR NEXT_RND
  JSR UPDATE_CURSORS
  JSR SPAWN
  JSR UPDATE_MISSILES
  JSR UPDATE_EXPL
  JSR COLLIDE
  LDA HUD_DIRTY
  BEQ .gl_noh
  LDA #$00
  STA HUD_DIRTY
  JSR DRAW_SCORE
.gl_noh:
  LDA AM_DIRTY
  BEQ .gl_noa
  LDA #$00
  STA AM_DIRTY
  JSR DRAW_AMMO
.gl_noa:
  JSR BUILD_SAT
  JSR VDP_INT_ON
  JSR CHECK_END
  JMP GAME_LOOP


; ---------------------------------------------------------------
; fine ondata / fine partita
; ---------------------------------------------------------------
CHECK_END:
  LDA T_ALIVE+1
  CLC
  ADC T_ALIVE+2
  ADC T_ALIVE+3
  ADC T_ALIVE+5
  ADC T_ALIVE+6
  ADC T_ALIVE+7
  STA NCITY
  BNE .ce_alive
  LDA #$00                     ; nessuna citta': niente nuovi lanci, poi fine partita
  STA SPAWN_LEFT
  LDA GO_TMR
  BNE .ce_dec
  LDA #100
  STA GO_TMR
  RTS
.ce_dec:
  DEC GO_TMR
  BNE .ce_ret
  JMP GAME_OVER
.ce_alive:
  LDA SPAWN_LEFT
  BNE .ce_ret
  LDX #(NM-1)
.ce_m:
  LDA M_ST,X
  BNE .ce_ret
  DEX
  BPL .ce_m
  LDX #(NE-1)
.ce_x:
  LDA X_ST,X
  BNE .ce_ret
  DEX
  BPL .ce_x
  JMP WAVE_END
.ce_ret:
  RTS


; ===============================================================
;  BONUS DI FINE ONDATA
; ===============================================================
WAVE_END:
  LDX #$FF
  TXS
  JSR HIDE_SPRITES
  LDA #40
  JSR WAIT_FRAMES
  JSR VDP_INT_OFF
  JSR CLEAR_PLAYFIELD
  ; moltiplicatore = min(ondata, 6)
  LDA WAVE
  CMP #7
  BCC .we_m
  LDA #6
.we_m:
  STA MULT
  ; citta' salve
  LDA T_ALIVE+1
  CLC
  ADC T_ALIVE+2
  ADC T_ALIVE+3
  ADC T_ALIVE+5
  ADC T_ALIVE+6
  ADC T_ALIVE+7
  STA NCITY
  ; missili rimasti
  LDA AMMO
  CLC
  ADC AMMO+1
  ADC AMMO+2
  STA NMIS
  LDA #$00
  STA B_LO
  STA B_MID
  LDX NCITY
  BEQ .we_cd
.we_c:
  SED
  CLC
  LDA B_MID
  ADC MULT
  STA B_MID
  CLD
  DEX
  BNE .we_c
.we_cd:
  LDX NMIS
  BEQ .we_md
  LDY MULT
  LDA MISS_PTS,Y
  STA T0
.we_mi:
  SED
  CLC
  LDA B_LO
  ADC T0
  STA B_LO
  LDA B_MID
  ADC #$00
  STA B_MID
  CLD
  DEX
  BNE .we_mi
.we_md:
  LDA B_LO
  STA ADLO
  LDA B_MID
  STA ADMID
  JSR ADD_SCORE
  ; testi
  LDA #<TXT_BONUS
  STA TP
  LDA #>TXT_BONUS
  STA TP+1
  JSR DRAW_TEXT
  LDA #$0F
  ASL A
  ASL A
  ASL A
  ASL A
  ORA #$01
  STA TCOL
  LDA #8
  STA CELLR
  LDA #25
  STA CELLC
  LDA NCITY
  JSR PUT_BCD
  LDA #10
  STA CELLR
  LDA #25
  STA CELLC
  LDA NMIS
  JSR BIN2BCD
  JSR PUT_BCD
  LDA #12
  STA CELLR
  LDA #$09
  ASL A
  ASL A
  ASL A
  ASL A
  ORA #$01
  STA TCOL
  LDA #21
  STA CELLC
  LDA B_MID
  JSR PUT_BCD
  LDA B_LO
  JSR PUT_BCD
  JSR DRAW_SCORE
  LDA #$00
  STA HUD_DIRTY
  LDA #W_BONUS
  LDX #2
  JSR SFX_WHISTLE
  JSR VDP_INT_ON
  LDA #150
  JSR WAIT_FRAMES
  INC WAVE
  SED
  CLC
  LDA WAVE_BCD
  ADC #$01
  STA WAVE_BCD
  CLD
  JMP WAVE_START


; ===============================================================
;  FINE PARTITA
; ===============================================================
GAME_OVER:
  LDX #$FF
  TXS
  JSR HIDE_SPRITES
  ; record
  LDA SCORE+2
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
  JSR CLEAR_PLAYFIELD
  LDA #<TXT_OVER
  STA TP
  LDA #>TXT_OVER
  STA TP+1
  JSR DRAW_TEXT
  LDA #$0F
  ASL A
  ASL A
  ASL A
  ASL A
  ORA #$01
  STA TCOL
  LDA #10
  STA CELLR
  LDA #18
  STA CELLC
  LDA SCORE+2
  JSR PUT_BCD
  LDA SCORE+1
  JSR PUT_BCD
  LDA SCORE
  JSR PUT_BCD
  LDA #12
  STA CELLR
  LDA #18
  STA CELLC
  LDA HISCORE+2
  JSR PUT_BCD
  LDA HISCORE+1
  JSR PUT_BCD
  LDA HISCORE
  JSR PUT_BCD
  JSR VDP_INT_ON
  LDA #CMD_LOSE                ; musica di sconfitta: si aspetta che finisca
  STA SND_CMD
  LDA #20
  JSR WAIT_FRAMES
.go_song:
  JSR WAIT_FRAME
  LDA SND_BUSY
  BNE .go_song
  JSR WAIT_FIRE
  JMP TITLE


; ---------------------------------------------------------------
; legge i due joystick (1 = premuto)
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

NEXT_RND:                      ; LFSR a 8 bit
  LDA RND
  ASL A
  BCC .nr_ok
  EOR #$1D
.nr_ok:
  STA RND
  RTS

; ---------------------------------------------------------------
; aspetta che i pulsanti siano rilasciati e poi premuti
; ---------------------------------------------------------------
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

WAIT_FRAMES:                   ; A = numero di frame (interrupt VDP acceso)
  STA T0
.wfs_l:
  JSR WAIT_FRAME
  DEC T0
  BNE .wfs_l
  RTS


; ===============================================================
;  MIRINI E FUOCO
; ===============================================================
UPDATE_CURSORS:
  LDX #$00
  JSR CURSOR_X
  LDX #$01
  JSR CURSOR_X
  RTS

; X = giocatore (0/1)
CURSOR_X:
  LDA P_JOY,X                  ; fronte di salita dei pulsanti
  AND #BTN_MASK
  STA T0
  LDA P_OLD,X
  EOR #$FF
  AND T0
  STA T1
  LDA T0
  STA P_OLD,X
  LDA P_ACT,X
  BNE .cx_act
  LDA T1                       ; mirino spento: si accende con un tasto
  BEQ .cx_ret
  LDA #$01
  STA P_ACT,X
  LDA #128
  STA P_CX,X
  LDA #96
  STA P_CY,X
.cx_ret:
  RTS
.cx_act:
  LDA P_JOY,X
  AND #%00001000               ; destra
  BEQ .cx_nr
  LDA P_CX,X
  CLC
  ADC #CUR_SPEED
  CMP #(CUR_XMAX+1)
  BCC .cx_r1
  LDA #CUR_XMAX
.cx_r1:
  STA P_CX,X
.cx_nr:
  LDA P_JOY,X
  AND #%00000100               ; sinistra
  BEQ .cx_nl
  LDA P_CX,X
  SEC
  SBC #CUR_SPEED
  BCS .cx_l1
  LDA #CUR_XMIN
.cx_l1:
  CMP #CUR_XMIN
  BCS .cx_l2
  LDA #CUR_XMIN
.cx_l2:
  STA P_CX,X
.cx_nl:
  LDA P_JOY,X
  AND #%00000001               ; su
  BEQ .cx_nu
  LDA P_CY,X
  SEC
  SBC #CUR_SPEED
  BCS .cx_u1
  LDA #CUR_YMIN
.cx_u1:
  CMP #CUR_YMIN
  BCS .cx_u2
  LDA #CUR_YMIN
.cx_u2:
  STA P_CY,X
.cx_nu:
  LDA P_JOY,X
  AND #%00000010               ; giu'
  BEQ .cx_nd
  LDA P_CY,X
  CLC
  ADC #CUR_SPEED
  CMP #(CUR_YMAX+1)
  BCC .cx_d1
  LDA #CUR_YMAX
.cx_d1:
  STA P_CY,X
.cx_nd:
  LDA T1
  BEQ .cx_end
  STA FBTN
  JSR FIRE_MISSILE
.cx_end:
  RTS

; ---------------------------------------------------------------
; X = mirino che spara (FBTN = pulsante appena premuto)
; ---------------------------------------------------------------
FIRE_MISSILE:
  STX CURI
  LDA FBTN
  AND #%00100000               ; tasto 2: base centrale
  BEQ .fi_near
  LDA AMMO+1
  BEQ .fi_near
  LDY #$01
  BRA .fi_go
.fi_near:                      ; base con missili piu' vicina al mirino
  LDA #$FF
  STA T2
  STA T3
  LDX #$00
.fi_loop:
  LDA AMMO,X
  BEQ .fi_next
  LDA BASE_X,X
  LDY CURI
  SEC
  SBC P_CX,Y
  BCS .fi_abs
  EOR #$FF
  CLC
  ADC #$01
.fi_abs:
  CMP T2
  BCS .fi_next
  STA T2
  STX T3
.fi_next:
  INX
  CPX #3
  BNE .fi_loop
  LDA T3
  CMP #$FF
  BNE .fi_have
  LDY CURI                     ; nessun missile disponibile: click
  LDA #W_EMPTY
  STA SMT1
  LDA P_CX,Y
  JSR SFX_WHISTLE_AT
  BRA .fi_ret
.fi_have:
  TAY
.fi_go:
  JSR ALLOC_SLOT
  BCS .fi_ret
  STY T4
  LDA BASE_X,Y
  STA LX0
  LDA #BASE_FY
  STA LY0
  LDY CURI
  LDA P_CX,Y
  STA LX1
  LDA P_CY,Y
  STA LY1
  JSR LINE_SETUP
  LDA #$01
  STA M_TYPE,X
  LDA #$00
  STA M_FLG,X
  STA M_SPF,X
  STA M_ACC,X
  LDY T4
  LDA BASE_SPD,Y
  STA M_SPI,X
  LDA AMMO,Y
  SEC
  SBC #$01
  STA AMMO,Y
  LDA #$01
  STA AM_DIRTY
  LDY T4                       ; fischio: laterale (sx / dx) o centrale (piu' acuto)
  LDX BASE_PAN,Y
  LDA BASE_WH,Y
  CMP #W_FIRE_SIDE
  BNE .fi_snd
  LDY CURI                     ; giocatore 2: sibilo laterale diverso
  BEQ .fi_snd
  LDA #W_FIRE_P2
.fi_snd:
  JSR SFX_WHISTLE
.fi_ret:
  LDX CURI
  RTS


; ===============================================================
;  MISSILI: linee di Bresenham, una struttura per slot
; ===============================================================
; cerca uno slot libero: X = slot (gia' marcato in volo), C=1 se pieno
ALLOC_SLOT:
  LDX #$00
.al_l:
  LDA M_ST,X
  BEQ .al_ok
  INX
  CPX #NM
  BNE .al_l
  SEC
  RTS
.al_ok:
  LDA #$01
  STA M_ST,X
  CLC
  RTS

; imposta la linea (LX0,LY0) -> (LX1,LY1) nello slot X
LINE_SETUP:
  LDA LX0
  STA M_OX,X
  STA M_X,X
  LDA LY0
  STA M_OY,X
  STA M_Y,X
  LDA LX1
  STA M_TX,X
  LDA LY1
  STA M_TY,X
  LDA LX1                      ; dx
  SEC
  SBC LX0
  BCS .ls_dxp
  EOR #$FF
  CLC
  ADC #$01
  LDY #$FF
  BRA .ls_dx
.ls_dxp:
  LDY #$01
.ls_dx:
  STA T0
  TYA
  STA M_SX,X
  LDA LY1                      ; dy
  SEC
  SBC LY0
  BCS .ls_dyp
  EOR #$FF
  CLC
  ADC #$01
  LDY #$FF
  BRA .ls_dy
.ls_dyp:
  LDY #$01
.ls_dy:
  STA T1
  TYA
  STA M_SY,X
  LDA T0
  CMP T1
  BCC .ls_ymaj
  LDA #$01                     ; asse maggiore X
  STA M_MAJ,X
  LDA T0
  STA M_LEN,X
  LDA T1
  STA M_MIN,X
  BRA .ls_end
.ls_ymaj:
  LDA #$00                     ; asse maggiore Y
  STA M_MAJ,X
  LDA T1
  STA M_LEN,X
  LDA T0
  STA M_MIN,X
.ls_end:
  LDA M_LEN,X
  STA M_REM,X
  LSR A
  STA M_ERR,X
  RTS

; avanza di un pixel lo slot X
STEP_LINE:
  LDA M_ERR,X
  CLC
  ADC M_MIN,X
  BCS .st_ov
  CMP M_LEN,X
  BCC .st_nov
.st_ov:
  SEC
  SBC M_LEN,X
  STA M_ERR,X
  LDY #$01                     ; passo anche sull'asse minore
  BRA .st_go
.st_nov:
  STA M_ERR,X
  LDY #$00
.st_go:
  LDA M_MAJ,X
  BNE .st_xmaj
  LDA M_Y,X
  CLC
  ADC M_SY,X
  STA M_Y,X
  CPY #$01
  BNE .st_end
  LDA M_X,X
  CLC
  ADC M_SX,X
  STA M_X,X
  BRA .st_end
.st_xmaj:
  LDA M_X,X
  CLC
  ADC M_SX,X
  STA M_X,X
  CPY #$01
  BNE .st_end
  LDA M_Y,X
  CLC
  ADC M_SY,X
  STA M_Y,X
.st_end:
  DEC M_REM,X
  RTS

; la scia dello slot X (passi fatti) va cancellata a partire dall'origine
TO_ERASE:
  LDA M_LEN,X
  SEC
  SBC M_REM,X
  STA T0
  LDA M_OX,X
  STA M_X,X
  LDA M_OY,X
  STA M_Y,X
  LDA M_LEN,X
  LSR A
  STA M_ERR,X
  LDA T0
  STA M_REM,X
  LDA #$02
  STA M_ST,X
  RTS

UPDATE_MISSILES:
  LDA #$00
  STA NACT_EN
  LDX #$00
.um_loop:
  LDA M_ST,X
  BEQ .um_next
  CMP #$02
  BEQ .um_erase
  JSR MISSILE_FLY
  BRA .um_next
.um_erase:
  JSR MISSILE_ERASE
.um_next:
  INX
  CPX #NM
  BNE .um_loop
  RTS

MISSILE_FLY:
  LDA M_TYPE,X
  BNE .mf_nocount
  INC NACT_EN
.mf_nocount:
  LDA M_ACC,X                  ; passi = parte intera + riporto della frazione
  CLC
  ADC M_SPF,X
  STA M_ACC,X
  LDA M_SPI,X
  ADC #$00
  STA NSTEP
  BEQ .mf_done
.mf_step:
  JSR STEP_LINE
  LDA M_REM,X
  BEQ .mf_arrive
  LDA M_Y,X
  CMP #GROUND_Y
  BCS .mf_nplot
  STA PY
  LDA M_X,X
  STA PX
  LDA M_TYPE,X
  BNE .mf_pl
  LDA #COL_ENEMY
  BRA .mf_pc
.mf_pl:
  LDA #COL_PLAYER
.mf_pc:
  STA PCOL
  JSR PLOT_SET
.mf_nplot:
  DEC NSTEP
  BNE .mf_step
.mf_done:
  LDA M_FLG,X                  ; MIRV: a quota M_SPLY la testata si divide
  AND #$01
  BEQ .mf_ret
  LDA M_Y,X
  CMP M_SPLY,X
  BCC .mf_ret
  LDA M_FLG,X
  AND #$FE
  STA M_FLG,X
  JSR MIRV_SPLIT
.mf_ret:
  RTS
.mf_arrive:
  LDA M_TYPE,X
  BNE .mf_pdet
  JMP ENEMY_IMPACT
.mf_pdet:
  JMP PLAYER_DETONATE

MISSILE_ERASE:
  LDA #ERASE_N
  STA NSTEP
.me_loop:
  LDA M_Y,X
  CMP #GROUND_Y
  BCS .me_skip
  STA PY
  LDA M_X,X
  STA PX
  JSR PLOT_CLR
.me_skip:
  LDA M_REM,X
  BEQ .me_free
  JSR STEP_LINE
  DEC NSTEP
  BNE .me_loop
  RTS
.me_free:
  LDA #$00
  STA M_ST,X
  RTS

; scelta di un sito bersaglio (preferibilmente vivo): A = indice
PICK_SITE:
  LDY #$08
.ps_try:
  JSR NEXT_RND
  LDA RND
  AND #$0F
  CMP #9
  BCS .ps_try
  TAX
  LDA T_ALIVE,X
  BNE .ps_ok
  DEY
  BNE .ps_try
.ps_ok:
  TXA
  RTS

; nuova testata nemica da (LX0,LY0). X = slot, C=1 se non c'e' posto
SPAWN_ENEMY:
  JSR ALLOC_SLOT
  BCS .se_ret
  STX SLOTV
  JSR PICK_SITE
  STA T6
  TAY
  LDA SITE_X,Y
  STA T5
  JSR NEXT_RND
  LDA RND
  AND #$07
  SEC
  SBC #$04
  CLC
  ADC T5
  STA LX1
  LDA #GROUND_Y
  STA LY1
  LDX SLOTV
  JSR LINE_SETUP
  LDA #$00
  STA M_TYPE,X
  STA M_FLG,X
  STA M_SPI,X
  LDA EN_SPF
  STA M_SPF,X
  LDA RND
  STA M_ACC,X
  LDA T6
  STA M_TG,X
  CLC
.se_ret:
  RTS

SPAWN:
  LDA SPAWN_LEFT
  BEQ .sp_ret
  LDA NACT_EN
  CMP MAX_ACT
  BCS .sp_ret
  DEC SPAWN_TMR
  BNE .sp_ret
  LDA SPAWN_DLY
  STA SPAWN_TMR
  JSR NEXT_RND
  LDA RND
  CMP #4
  BCS .sp_c1
  LDA #4
.sp_c1:
  CMP #252
  BCC .sp_c2
  LDA #251
.sp_c2:
  STA LX0
  LDA #SPAWN_Y
  STA LY0
  JSR SPAWN_ENEMY
  BCS .sp_ret
  LDA #W_ENEMY                 ; sibilo discendente, dal lato da cui arriva
  STA SMT1
  LDA LX0
  JSR SFX_WHISTLE_AT
  LDA WAVE                     ; MIRV dall'ondata 3: una testata su 4
  CMP #3
  BCC .sp_nom
  JSR NEXT_RND
  LDA RND
  AND #$03
  BNE .sp_nom
  LDA #$03                     ; bit0 = si dividera', bit1 = testata MIRV
  STA M_FLG,X
  JSR NEXT_RND
  LDA RND
  AND #$1F
  CLC
  ADC #56
  STA M_SPLY,X
.sp_nom:
  DEC SPAWN_LEFT
.sp_ret:
  RTS

MIRV_SPLIT:                    ; la testata X lancia due figlie dalla sua posizione
  PHX
  LDA M_X,X
  STA LX0
  LDA M_Y,X
  STA LY0
  LDA #W_MIRV
  STA SMT1
  LDA LX0
  JSR SFX_WHISTLE_AT
  LDA #$02
  STA MCNT
.ms_l:
  JSR SPAWN_ENEMY
  BCS .ms_n
  LDA #$04                     ; bit2 = figlia di una MIRV
  STA M_FLG,X
.ms_n:
  DEC MCNT
  BNE .ms_l
  PLX
  RTS

ENEMY_IMPACT:                  ; la testata X e' arrivata a terra
  PHX
  LDA M_TX,X
  STA EXX
  LDA M_TG,X
  JSR DESTROY_SITE
  LDA #GROUND_Y
  STA EXY
  JSR NEW_EXPL
  LDA #S_BIG
  LDX #2
  JSR SFX_BOOM
  PLX
  JMP TO_ERASE

PLAYER_DETONATE:               ; il nostro missile X e' arrivato al mirino
  PHX
  LDA M_TX,X
  STA EXX
  LDA M_TY,X
  STA EXY
  JSR NEW_EXPL
  LDA #S_SMALL
  STA SMT1
  LDA EXX
  JSR SFX_BOOM_AT
  PLX
  JMP TO_ERASE

ENEMY_KILLED:                  ; X = slot colpito da un'esplosione
  LDA M_FLG,X                  ; suono diverso per tipo di nemico
  AND #$02
  BEQ .ek_nm
  LDA #W_KILL_MIRV             ; testata MIRV (portatrice)
  BRA .ek_w
.ek_nm:
  LDA M_FLG,X
  AND #$04
  BEQ .ek_pl
  LDA #W_KILL_CHILD            ; figlia di una MIRV
  BRA .ek_w
.ek_pl:
  LDA #W_KILL_PLAIN            ; testata normale
.ek_w:
  STA SMT1
  LDA M_X,X
  JSR SFX_WHISTLE_AT
  LDA #S_SMALL
  STA SMT1
  LDA M_X,X
  JSR SFX_BOOM_AT
  LDA #$25
  STA ADLO
  LDA #$00
  STA ADMID
  JSR ADD_SCORE
  JMP TO_ERASE

; A = sito colpito
DESTROY_SITE:
  TAX
  LDA T_ALIVE,X
  BEQ .dss_ret
  LDA #$00
  STA T_ALIVE,X
  LDA SITE_BASE,X
  CMP #$FF
  BEQ .dss_draw
  TAY
  LDA #$00
  STA AMMO,Y
  LDA #$01
  STA AM_DIRTY
.dss_draw:
  JSR DRAW_SITE
.dss_ret:
  RTS

; punteggio: somma ADLO / ADMID (BCD) a SCORE
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
  LDA #$01
  STA HUD_DIRTY
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
;  COLLISIONI: testata nemica dentro una esplosione
; ===============================================================
COLLIDE:
  LDX #$00
.co_m:
  LDA M_ST,X
  CMP #$01
  BNE .co_nm
  LDA M_TYPE,X
  BNE .co_nm
  LDY #$00
.co_e:
  LDA X_ST,Y
  BEQ .co_ne
  LDA X_RAD,Y
  BEQ .co_ne
  STA T0                       ; raggio
  LDA M_X,X
  SEC
  SBC X_CX,Y
  BCS .co_dx
  EOR #$FF
  CLC
  ADC #$01
.co_dx:
  STA T1                       ; |dx|
  CMP T0
  BEQ .co_xok
  BCS .co_ne
.co_xok:
  LDA M_Y,X
  SEC
  SBC X_CY,Y
  BCS .co_dy
  EOR #$FF
  CLC
  ADC #$01
.co_dy:
  STA T2                       ; |dy|
  CMP T0
  BEQ .co_yok
  BCS .co_ne
.co_yok:
  CLC
  ADC T1
  STA T3                       ; |dx|+|dy|
  LDA T0
  LSR A
  CLC
  ADC T0                       ; 1.5 * raggio (ottagono)
  CMP T3
  BCC .co_ne
  JSR ENEMY_KILLED
  BRA .co_nm
.co_ne:
  INY
  CPY #NE
  BNE .co_e
.co_nm:
  INX
  CPX #NM
  BNE .co_m
  RTS


; ===============================================================
;  ESPLOSIONI: blocco 4x4 tile centrato su un angolo della griglia
; ===============================================================
NEW_EXPL:                      ; (EXX,EXY) = punto di scoppio
  LDA EXX
  CLC
  ADC #$04
  BCC .ne_x1
  LDA #$F8
.ne_x1:
  AND #$F8
  CMP #16
  BCS .ne_x2
  LDA #16
.ne_x2:
  CMP #241
  BCC .ne_x3
  LDA #240
.ne_x3:
  STA T4
  LDA EXY
  CLC
  ADC #$04
  AND #$F8
  CMP #16
  BCS .ne_y2
  LDA #16
.ne_y2:
  CMP #177
  BCC .ne_y3
  LDA #176
.ne_y3:
  STA T5
  LDX #$00
.ne_find:
  LDA X_ST,X
  BEQ .ne_ok
  INX
  CPX #NE
  BNE .ne_find
  RTS
.ne_ok:
  LDA #$01
  STA X_ST,X
  STA X_TMR,X
  LDA T4
  STA X_CX,X
  LDA T5
  STA X_CY,X
  LDA #$00
  STA X_STG,X
  STA X_RAD,X
  RTS

UPDATE_EXPL:
  LDA #EXPL_BUDGET
  STA BUDGET
  LDX #$00
.ue_l:
  LDA X_ST,X
  BEQ .ue_n
  LDA X_TMR,X
  BEQ .ue_due
  DEC X_TMR,X
  BNE .ue_n
.ue_due:
  LDA BUDGET
  BEQ .ue_n                    ; niente budget: resta in ritardo
  DEC BUDGET
  JSR EXPL_ADVANCE
.ue_n:
  INX
  CPX #NE
  BNE .ue_l
  RTS

EXPL_ADVANCE:                  ; X = esplosione
  LDA X_STG,X
  CMP #SEQ_LEN
  BCS .ea_end
  TAY
  LDA EXPL_SEQ,Y
  STA SHAPEV
  TAY
  LDA EXPL_RAD,Y
  STA X_RAD,X
  INC X_STG,X
  LDA #EXPL_HOLD
  STA X_TMR,X
  JMP DRAW_EXPL
.ea_end:
  LDA #$FF                     ; forma vuota: ripristina lo schermo
  STA SHAPEV
  JSR DRAW_EXPL
  LDA #$00
  STA X_ST,X
  STA X_RAD,X
  RTS

; ridisegna il blocco 4x4 dell'esplosione X con la forma SHAPEV ($FF = nessuna)
DRAW_EXPL:
  LDA X_STG,X
  AND #$03
  TAY
  LDA FIRE_COL,Y
  STA FCOL
  LDA X_CX,X
  LSR A
  LSR A
  LSR A
  SEC
  SBC #$02
  STA EC0
  LDA X_CY,X
  LSR A
  LSR A
  LSR A
  SEC
  SBC #$02
  STA ER0
  LDA SHAPEV
  CMP #$FF
  BEQ .de_zero
  LSR A                        ; SHAPEV * 128
  STA T0
  LDA #$00
  ROR A
  CLC
  ADC #<EXPL_SHAPES
  STA ESH
  LDA T0
  ADC #>EXPL_SHAPES
  STA ESH+1
  LDA #$08
  STA ESTEP
  BRA .de_go
.de_zero:
  LDA #<ZEROS
  STA ESH
  LDA #>ZEROS
  STA ESH+1
  LDA #$00
  STA ESTEP
.de_go:
  LDA ESH
  STA ECP
  LDA ESH+1
  STA ECP+1
  LDA #$00
  STA EI
.de_cell:
  LDA EI
  AND #$03
  CLC
  ADC EC0
  STA CELLC
  LDA EI
  LSR A
  LSR A
  CLC
  ADC ER0
  STA CELLR
  JSR CELL_SETUP
  LDA T0                       ; pattern = copia in RAM | forma
  STA VREG
  LDA T1
  ORA #$40
  STA VREG
  LDY #$00
.de_p:
  LDA (SPTR),Y
  ORA (ECP),Y
  STA VDATA
  INY
  CPY #$08
  BNE .de_p
  LDA T0                       ; colore: fuoco dove c'e' la forma, altrimenti l'originale
  STA VREG
  LDA T1
  ORA #$60
  STA VREG
  LDY #$00
.de_c:
  LDA (ECP),Y
  BEQ .de_k
  LDA FCOL
  BRA .de_w
.de_k:
  LDA (PTR2),Y
.de_w:
  STA VDATA
  INY
  CPY #$08
  BNE .de_c
  LDA ECP                      ; prossima cella della forma
  CLC
  ADC ESTEP
  STA ECP
  BCC .de_n
  INC ECP+1
.de_n:
  INC EI
  LDA EI
  CMP #16
  BNE .de_cell
  RTS


; ===============================================================
;  PIXEL (con copia in RAM della bitmap e dei colori)
; ===============================================================
; indirizzo cella/riga: T0 = (x & $F8) | (y & 7), T1 = y / 8
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

PLOT_SET:                      ; accende (PX,PY) con colore PCOL
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

PLOT_CLR:                      ; spegne (PX,PY)
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
;  CELLE 8x8 (copia in RAM + VRAM)
; ===============================================================
; da CELLC/CELLR: T0 = col*8, T1 = riga, SPTR = pattern in RAM, PTR2 = colori in RAM
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

; copia la cella (copia in RAM) nella VRAM: richiede CELL_SETUP
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

; disegna il tile a PTR (8 pattern + 8 colori) in (CELLC,CELLR); PTR avanza di 16
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

; A = codice ASCII ($20-$5F), in (CELLC,CELLR) con colore TCOL
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

; A = byte BCD: due cifre, CELLC avanza di 2
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

; record: riga, colonna, colore (fg), caratteri..., 0   (fine lista: riga = $FF)
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

; parole grandi: riga, colonna, n, id lettere... (fine lista: riga = $FF)
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
  STA T7                       ; numero di lettere
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


; ===============================================================
;  SCHERMO FISSO: terreno, citta', basi, punteggi
; ===============================================================
DRAW_GROUND:
  LDA #23
  STA CELLR
  LDA #$00
  STA CELLC
.dg_l:
  LDA #<TILE_GROUND
  STA PTR
  LDA #>TILE_GROUND
  STA PTR+1
  JSR BLIT_CELL
  INC CELLC
  LDA CELLC
  CMP #32
  BNE .dg_l
  RTS

; X = sito (0-8): disegna intatto o distrutto. Conserva X.
DRAW_SITE:
  STX SITEV
  LDA SITE_COL,X
  STA SITE_C0
  LDA SITE_BASE,X
  CMP #$FF
  BEQ .dsi_city
  LDA #4
  STA SITE_W
  LDA T_ALIVE,X
  BEQ .dsi_brub
  LDA #<TILES_BASE
  STA PTR
  LDA #>TILES_BASE
  STA PTR+1
  BRA .dsi_go
.dsi_brub:
  LDA #<TILES_BASE_RUB
  STA PTR
  LDA #>TILES_BASE_RUB
  STA PTR+1
  BRA .dsi_go
.dsi_city:
  LDA #2
  STA SITE_W
  LDA T_ALIVE,X
  BEQ .dsi_crub
  LDA #<TILES_CITY
  STA PTR
  LDA #>TILES_CITY
  STA PTR+1
  BRA .dsi_go
.dsi_crub:
  LDA #<TILES_CITY_RUB
  STA PTR
  LDA #>TILES_CITY_RUB
  STA PTR+1
.dsi_go:
  LDA #21
  STA CELLR
.dsi_row:
  LDA SITE_C0
  STA CELLC
  LDA SITE_W
  STA SITE_WC
.dsi_col:
  JSR BLIT_CELL
  INC CELLC
  DEC SITE_WC
  BNE .dsi_col
  INC CELLR
  LDA CELLR
  CMP #23
  BNE .dsi_row
  LDX SITEV
  RTS

DRAW_SCORE:
  LDA #$00
  STA CELLR
  LDA #$F1
  STA TCOL
  LDA #7
  STA CELLC
  LDA SCORE+2
  JSR PUT_BCD
  LDA SCORE+1
  JSR PUT_BCD
  LDA SCORE
  JSR PUT_BCD
  LDA #26
  STA CELLC
  LDA WAVE_BCD
  JSR PUT_BCD
  RTS

; missili rimasti sotto ogni base (due cifre sul terreno)
DRAW_AMMO:
  LDX #$00
.da_l:
  STX AMI
  LDA AMMO,X
  LDY #$20
  CMP #10
  BCC .da_o
  SEC
  SBC #10
  LDY #$31
.da_o:
  ORA #$30
  STA T6
  STY T7
  LDA AMMO_COL,X
  STA CELLC
  LDA #23
  STA CELLR
  LDA #$1A
  STA TCOL
  LDA T7
  JSR PUT_CHAR
  INC CELLC
  LDA T6
  JSR PUT_CHAR
  LDX AMI
  INX
  CPX #3
  BNE .da_l
  RTS


; ===============================================================
;  SPRITE (mirini) e NMI
; ===============================================================
BUILD_SAT:
  LDX #$00
  LDY #$00
.bs_l:
  LDA P_ACT,X
  BEQ .bs_hide
  LDA P_CY,X
  SEC
  SBC #$08
  STA SAT_BUFFER,Y
  LDA P_CX,X
  SEC
  SBC #$07
  STA SAT_BUFFER+1,Y
  LDA #$00
  STA SAT_BUFFER+2,Y
  LDA CUR_COL,X
  STA SAT_BUFFER+3,Y
  BRA .bs_n
.bs_hide:
  LDA #HIDE_Y
  STA SAT_BUFFER,Y
.bs_n:
  INY
  INY
  INY
  INY
  INX
  CPX #$02
  BNE .bs_l
  RTS

HIDE_SPRITES:
  LDA #HIDE_Y
  STA SAT_BUFFER
  STA SAT_BUFFER+4
  RTS

; NMI (vblank): unico punto che scrive la Sprite Attribute Table.
NMI_TASK:
  INC FRAME_CNT
  LDA VREG                ; leggi stato VDP (azzera F e C e il latch dei byte)
  LDA #<VDP_SPRITE_ATT_BASE
  STA VREG
  LDA #(VDP_WRITE_VRAM_BIT | >VDP_SPRITE_ATT_BASE)
  STA VREG
  LDX #$00
.copy_sat:
  LDA SAT_BUFFER,X
  STA VDATA
  INX
  CPX #9                  ; 2 sprite x 4 byte + Y=$D0 della 3a voce
  BNE .copy_sat
  JSR SND_TICK            ; musica ed effetti sonori
  RTS                     ; NMI_HANDLER del BIOS rilegge VREG e fa RTI

WAIT_FRAME:               ; aspetta il prossimo NMI (1 frame = 1/60 s)
  LDA FRAME_CNT
  CMP LAST_FRAME
  BEQ WAIT_FRAME
  STA LAST_FRAME
  RTS

; spegne l'interrupt del VDP subito dopo un NMI (ne arriva un altro fra ~16 ms)
VDP_INT_OFF:
  LDA VINT
  BEQ .io_ret             ; gia' spento
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

; SAT: 0 = mirino P1, 1 = mirino P2, poi Y=$D0 = fine lista
SAT_BUFFER:    .byte HIDE_Y,$00,$00,$0F
               .byte HIDE_Y,$00,$00,$0B
               .byte $D0


; ===============================================================
;  VDP
; ===============================================================
; riga di inizio in A, numero di righe in X: azzera pattern e colori (nero su nero)
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

CLEAR_PLAYFIELD:               ; righe 1-20
  LDA #$01
  LDX #20
  JMP CLEAR_ROWS

; name table: tile = posizione (0-255 in ognuno dei 3 terzi) => bitmap piena
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

LOAD_SPRITES:                  ; pattern degli sprite a $1800
  LDA #$00
  STA VREG
  LDA #(VDP_WRITE_VRAM_BIT | $18)
  STA VREG
  LDY #$00
.ls_l:
  LDA CROSS_SPR,Y
  STA VDATA
  INY
  CPY #32
  BNE .ls_l
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
                               ;R4: pattern $0000 | R5: SAT $3B00 | R6: sprite pattern $1800 | R7: sfondo nero



; ===============================================================
;  SONORO  -  due AY-3-8910 (sinistro / destro = stereo)
;  Tutto il suono e' suonato da SND_TICK, chiamata dall'NMI a 60 Hz.
;  Il main loop non scrive mai sugli AY: lascia solo richieste
;  (SND_CMD, SFX_WHISTLE, SFX_BOOM), cosi' non ci sono conflitti.
;  Gli AY si scrivono dagli shadow SH_L / SH_R (registri 0-10).
;  Canali per chip in gioco: A = fischio (tono), B = rumore
;  (esplosione), C = botto grave (tono).
; ===============================================================

; chiamata una volta da RESET (interrupt VDP ancora spento)
SND_INIT:
  LDA #$A5
  STA SND_RND
  LDA #$00
  STA SND_CMD
  STA SND_PH
  JMP SND_GAME_MODE

SND_CLEAR_SH:                   ; tutti i registri shadow a 0
  LDX #10
  LDA #$00
.cs_l:
  STA SH_L,X
  STA SH_R,X
  DEX
  BPL .cs_l
  RTS

; modalita' gioco: silenzio, mixer = tono A + rumore B + tono C
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

; scrive i registri 0-10 dei due shadow sui due AY
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
; chiamata dall'NMI: A,X,Y salvati qui
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
  SBC #CMD_TITLE                ; 0 = titolo, 1 = sconfitta
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
; avvia una canzone: A = 0 titolo, 1 sconfitta
; ---------------------------------------------------------------
SND_START:
  ASL A
  ASL A
  STA SN0                       ; canzone * 4
  JSR SND_CLEAR_SH
  LDA #$38                      ; sinistro: 3 toni
  STA SH_L+7
  LDA #$2A                      ; destro: tono A, rumore B (batteria), tono C
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
  STA TR_CT,X                   ; il primo DEC porta a 0 -> legge subito la prima nota
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
; legge il prossimo evento della traccia X: .byte nota, durata (frame); $FF = fine
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
  LDA #$00                      ; fine traccia
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
  BEQ .mf_vol                   ; pausa: volume 0
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
; un frame di musica: avanza le 4 tracce e riempie gli shadow
; ---------------------------------------------------------------
MUS_TICK:
  LDX #$02                      ; tracce a tono: 0 melodia, 1 arpeggio, 2 basso
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
  LDX #$03                      ; traccia 3: batteria
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
  ; ---- melodia: su entrambi i chip, il destro scordato di 1 passo (effetto chorus);
  ;      vibrato sulle note lunghe e non troppo acute
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
  ; ---- arpeggio: solo chip sinistro, canale B
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
  ; ---- basso: entrambi i chip, canale C
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
  ; ---- batteria: chip destro, rumore sul canale B
  LDX TR_NOTE+3
  LDA DRUM_NP,X
  STA SH_R+6
  LDA TR_VOL+3
  STA SH_R+9
  ; ---- canzone finita?
  LDA TR_ACT
  ORA TR_ACT+1
  ORA TR_ACT+2
  ORA TR_ACT+3
  BNE .mt_end
  JSR SND_GAME_MODE             ; silenzio, SND_BUSY = 0
.mt_end:
  RTS

; ---------------------------------------------------------------
; effetti di gioco (un frame, chiamata dall'NMI). Chip 0 = sinistro, 1 = destro.
;   fischio: id in WH_ID, tabelle WH_*  (canale A)
;   esplosione: id in EX_ID, tabelle EX_*  (rumore B + botto C)
; ---------------------------------------------------------------
SFX_TICK:
  LDA SND_RND                   ; LFSR per il crepitio dell'esplosione
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
  TAY                           ; Y = chip * 16 = offset dello shadow (SH_R = SH_L + 16)
  LDA #$00
  STA SH_L+8,Y
  STA SH_L+9,Y
  STA SH_L+10,Y
  LDA WH_ID,X                   ; ---- fischio
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
  LDX SND_T1                    ; ---- esplosione
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
  LDA SND_RND                   ; crepitio: -1 a caso
  LSR A
  LDA EX_NV,X
  SBC #$00
.sf_e1:
  STA SH_L+9,Y
  LDA EX_NP,X
  CPY #$00
  BEQ .sf_e2
  CLC
  ADC #$03                      ; chip destro: rumore leggermente diverso
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
.sf_next:
  LDX SND_T1
  DEX
  BMI .sf_done
  JMP .sf_chip
.sf_done:
  RTS

; ---------------------------------------------------------------
; richieste dal main loop (conservano A, X, Y)
;   pan: X = 0 sinistro, 1 destro, 2 entrambi
; ---------------------------------------------------------------
PAN_OF_X:                       ; A = x (pixel) -> X = pan
  CMP #80
  BCC .px_l
  CMP #177
  BCS .px_r
  LDX #$02
  RTS
.px_l:
  LDX #$00
  RTS
.px_r:
  LDX #$01
  RTS

SFX_WHISTLE:                    ; A = id fischio (W_*), X = pan
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

SFX_WHISTLE_AT:                 ; A = x (pixel), SMT1 = id fischio: pan automatico
  PHX
  JSR PAN_OF_X
  LDA SMT1
  JSR SFX_WHISTLE
  PLX
  RTS

SB_SET:                         ; X = chip, SMT0 = id esplosione
  LDA EX_ID,X
  CMP #S_BIG
  BNE .sbs_set
  LDA SMT0                      ; un botto piccolo non interrompe uno grande
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

SFX_BOOM_AT:                    ; A = x (pixel), SMT1 = id esplosione
  PHX
  JSR PAN_OF_X
  LDA SMT1
  JSR SFX_BOOM
  PLX
  RTS

; ===============================================================
;  TABELLE
; ===============================================================
BITMASK:    .byte $80,$40,$20,$10,$08,$04,$02,$01
ZEROS:      .byte $00,$00,$00,$00,$00,$00,$00,$00
SITE_COL:   .byte 0,5,8,11,14,19,22,25,28        ; colonna iniziale di ogni sito
SITE_X:     .byte 16,48,72,96,128,160,184,208,240 ; centro (pixel)
SITE_BASE:  .byte 0,$FF,$FF,$FF,1,$FF,$FF,$FF,2   ; numero base, $FF = citta'
BASE_X:     .byte 16,128,240
BASE_SPD:   .byte 3,4,3                           ; pixel per frame dei nostri missili
AMMO_COL:   .byte 1,15,29
BASE_PAN:   .byte 0,2,1                           ; sibilo: sinistra / entrambi / destra
BASE_WH:    .byte W_FIRE_SIDE,W_FIRE_CENTER,W_FIRE_SIDE
CUR_COL:    .byte $0F,$0B                         ; mirino P1 bianco, P2 giallo
FIRE_COL:   .byte $F1,$B1,$91,$B1                 ; colori del fuoco
MISS_PTS:   .byte $00,$05,$10,$15,$20,$25,$30     ; bonus per missile (BCD) x moltiplicatore

; ===============================================================
;  DATI GRAFICI (generati)
; ===============================================================
; font 5x7: caratteri ASCII $20-$5F, 8 byte ciascuno (tile del gioco precedente)
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
; sprite 0: mirino (16x16), centro del mirino = pixel (7,7)
CROSS_SPR:
  .byte $00,$01,$01,$01,$01,$01,$00,$7D
  .byte $00,$01,$01,$01,$01,$01,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$7C
  .byte $00,$00,$00,$00,$00,$00,$00,$00
; citta' intatta: 4 tile (alto-sx, alto-dx, basso-sx, basso-dx), 16 byte l'uno (8 pattern + 8 colori)
TILES_CITY:
  .byte $00,$00,$00,$02,$02,$33,$37,$7B,$51,$51,$51,$51,$51,$51,$51,$51
  .byte $00,$00,$00,$00,$30,$36,$7A,$7B,$51,$51,$51,$51,$51,$51,$51,$51
  .byte $7B,$5A,$7B,$4A,$7B,$5A,$7B,$FF,$51,$51,$51,$51,$51,$51,$51,$51
  .byte $FE,$D6,$FE,$96,$FE,$D6,$FE,$FF,$51,$51,$51,$51,$51,$51,$51,$51
; citta' distrutta
TILES_CITY_RUB:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$61,$61,$61,$61,$61,$61,$61,$61
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$61,$61,$61,$61,$61,$61,$61,$61
  .byte $00,$00,$00,$00,$08,$39,$7D,$FF,$61,$61,$61,$61,$61,$61,$61,$61
  .byte $00,$00,$00,$00,$30,$3A,$BF,$FF,$61,$61,$61,$61,$61,$61,$61,$61
; base intatta 4x2 tile (riga alta poi riga bassa)
TILES_BASE:
  .byte $00,$00,$00,$01,$03,$07,$0F,$1F,$31,$31,$31,$31,$31,$31,$31,$31
  .byte $3C,$7F,$FE,$FE,$FE,$FE,$FE,$FE,$31,$31,$31,$31,$31,$31,$31,$31
  .byte $3C,$FE,$7F,$7F,$7F,$7F,$7F,$7F,$31,$31,$31,$31,$31,$31,$31,$31
  .byte $00,$00,$00,$80,$C0,$E0,$F0,$F8,$31,$31,$31,$31,$31,$31,$31,$31
  .byte $3F,$7F,$FF,$FF,$FF,$FF,$FF,$FF,$31,$31,$31,$31,$31,$31,$31,$31
  .byte $FE,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$31,$31,$31,$31,$31,$31,$31,$31
  .byte $7F,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$31,$31,$31,$31,$31,$31,$31,$31
  .byte $FC,$FE,$FF,$FF,$FF,$FF,$FF,$FF,$31,$31,$31,$31,$31,$31,$31,$31
; base distrutta
TILES_BASE_RUB:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$61,$61,$61,$61,$61,$61,$61,$61
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$61,$61,$61,$61,$61,$61,$61,$61
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$61,$61,$61,$61,$61,$61,$61,$61
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$61,$61,$61,$61,$61,$61,$61,$61
  .byte $00,$00,$00,$00,$00,$00,$04,$FF,$61,$61,$61,$61,$61,$61,$61,$61
  .byte $00,$00,$00,$00,$00,$94,$B4,$FF,$61,$61,$61,$61,$61,$61,$61,$61
  .byte $00,$00,$00,$00,$00,$02,$63,$FF,$61,$61,$61,$61,$61,$61,$61,$61
  .byte $00,$00,$00,$00,$00,$40,$4C,$FF,$61,$61,$61,$61,$61,$61,$61,$61
; terreno: pattern vuoto, colore giallo scuro (la prima riga piu' chiara)
TILE_GROUND:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$1B,$1A,$1A,$1A,$1A,$1A,$1A,$1A
; lettere grandi (16x16, 4 tile ciascuna): M I S L E C O A N D
BIGFONT:
  .byte $00,$38,$38,$3E,$3E,$3B,$3B,$3B,$81,$81,$81,$91,$91,$91,$91,$A1
  .byte $00,$38,$38,$F8,$F8,$B8,$B8,$B8,$81,$81,$81,$91,$91,$91,$91,$A1
  .byte $3B,$38,$38,$38,$38,$38,$38,$00,$A1,$B1,$B1,$B1,$B1,$F1,$F1,$F1
  .byte $B8,$38,$38,$38,$38,$38,$38,$00,$A1,$B1,$B1,$B1,$B1,$F1,$F1,$F1
  .byte $00,$0F,$0F,$03,$03,$03,$03,$03,$81,$81,$81,$91,$91,$91,$91,$A1
  .byte $00,$E0,$E0,$80,$80,$80,$80,$80,$81,$81,$81,$91,$91,$91,$91,$A1
  .byte $03,$03,$03,$03,$03,$0F,$0F,$00,$A1,$B1,$B1,$B1,$B1,$F1,$F1,$F1
  .byte $80,$80,$80,$80,$80,$E0,$E0,$00,$A1,$B1,$B1,$B1,$B1,$F1,$F1,$F1
  .byte $00,$0F,$0F,$38,$38,$38,$38,$0F,$81,$81,$81,$91,$91,$91,$91,$A1
  .byte $00,$E0,$E0,$38,$38,$00,$00,$E0,$81,$81,$81,$91,$91,$91,$91,$A1
  .byte $0F,$00,$00,$38,$38,$0F,$0F,$00,$A1,$B1,$B1,$B1,$B1,$F1,$F1,$F1
  .byte $E0,$38,$38,$38,$38,$E0,$E0,$00,$A1,$B1,$B1,$B1,$B1,$F1,$F1,$F1
  .byte $00,$38,$38,$38,$38,$38,$38,$38,$81,$81,$81,$91,$91,$91,$91,$A1
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$81,$81,$81,$91,$91,$91,$91,$A1
  .byte $38,$38,$38,$38,$38,$3F,$3F,$00,$A1,$B1,$B1,$B1,$B1,$F1,$F1,$F1
  .byte $00,$00,$00,$00,$00,$F8,$F8,$00,$A1,$B1,$B1,$B1,$B1,$F1,$F1,$F1
  .byte $00,$3F,$3F,$38,$38,$38,$38,$3F,$81,$81,$81,$91,$91,$91,$91,$A1
  .byte $00,$F8,$F8,$00,$00,$00,$00,$E0,$81,$81,$81,$91,$91,$91,$91,$A1
  .byte $3F,$38,$38,$38,$38,$3F,$3F,$00,$A1,$B1,$B1,$B1,$B1,$F1,$F1,$F1
  .byte $E0,$00,$00,$00,$00,$F8,$F8,$00,$A1,$B1,$B1,$B1,$B1,$F1,$F1,$F1
  .byte $00,$0F,$0F,$38,$38,$38,$38,$38,$81,$81,$81,$91,$91,$91,$91,$A1
  .byte $00,$E0,$E0,$38,$38,$00,$00,$00,$81,$81,$81,$91,$91,$91,$91,$A1
  .byte $38,$38,$38,$38,$38,$0F,$0F,$00,$A1,$B1,$B1,$B1,$B1,$F1,$F1,$F1
  .byte $00,$00,$00,$38,$38,$E0,$E0,$00,$A1,$B1,$B1,$B1,$B1,$F1,$F1,$F1
  .byte $00,$0F,$0F,$38,$38,$38,$38,$38,$81,$81,$81,$91,$91,$91,$91,$A1
  .byte $00,$E0,$E0,$38,$38,$38,$38,$38,$81,$81,$81,$91,$91,$91,$91,$A1
  .byte $38,$38,$38,$38,$38,$0F,$0F,$00,$A1,$B1,$B1,$B1,$B1,$F1,$F1,$F1
  .byte $38,$38,$38,$38,$38,$E0,$E0,$00,$A1,$B1,$B1,$B1,$B1,$F1,$F1,$F1
  .byte $00,$03,$03,$0E,$0E,$38,$38,$38,$81,$81,$81,$91,$91,$91,$91,$A1
  .byte $00,$80,$80,$E0,$E0,$38,$38,$38,$81,$81,$81,$91,$91,$91,$91,$A1
  .byte $38,$3F,$3F,$38,$38,$38,$38,$00,$A1,$B1,$B1,$B1,$B1,$F1,$F1,$F1
  .byte $38,$F8,$F8,$38,$38,$38,$38,$00,$A1,$B1,$B1,$B1,$B1,$F1,$F1,$F1
  .byte $00,$38,$38,$38,$38,$3E,$3E,$3B,$81,$81,$81,$91,$91,$91,$91,$A1
  .byte $00,$38,$38,$38,$38,$38,$38,$B8,$81,$81,$81,$91,$91,$91,$91,$A1
  .byte $3B,$38,$38,$38,$38,$38,$38,$00,$A1,$B1,$B1,$B1,$B1,$F1,$F1,$F1
  .byte $B8,$F8,$F8,$38,$38,$38,$38,$00,$A1,$B1,$B1,$B1,$B1,$F1,$F1,$F1
  .byte $00,$3F,$3F,$38,$38,$38,$38,$38,$81,$81,$81,$91,$91,$91,$91,$A1
  .byte $00,$E0,$E0,$38,$38,$38,$38,$38,$81,$81,$81,$91,$91,$91,$91,$A1
  .byte $38,$38,$38,$38,$38,$3F,$3F,$00,$A1,$B1,$B1,$B1,$B1,$F1,$F1,$F1
  .byte $38,$38,$38,$38,$38,$E0,$E0,$00,$A1,$B1,$B1,$B1,$B1,$F1,$F1,$F1
; esplosioni: 8 forme, ognuna 4x4 tile (16 x 8 byte) centrate sull'angolo comune dei 4 tile centrali
EXPL_SHAPES:
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$03,$03
  .byte $00,$00,$00,$00,$00,$00,$C0,$C0
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $03,$03,$00,$00,$00,$00,$00,$00
  .byte $C0,$C0,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$07,$0F,$0F,$0F
  .byte $00,$00,$00,$00,$E0,$F0,$F0,$F0
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $0F,$0F,$0F,$07,$00,$00,$00,$00
  .byte $F0,$F0,$F0,$E0,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$07,$1F,$1F,$3F,$3F,$3F
  .byte $00,$00,$E0,$F8,$F8,$FC,$FC,$FC
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $3F,$3F,$3F,$1F,$1F,$07,$00,$00
  .byte $FC,$FC,$FC,$F8,$F8,$E0,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $0F,$1F,$3F,$7F,$FF,$FF,$FF,$FF
  .byte $F0,$F8,$FC,$FE,$FF,$FF,$FF,$FF
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $FF,$FF,$FF,$FF,$7F,$3F,$1F,$0F
  .byte $FF,$FF,$FF,$FF,$FE,$FC,$F8,$F0
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$0F,$3F
  .byte $00,$00,$00,$00,$00,$00,$F0,$FC
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$01,$01,$03,$03,$03,$03
  .byte $7F,$FF,$FF,$FF,$FF,$FF,$FF,$FF
  .byte $FE,$FF,$FF,$FF,$FF,$FF,$FF,$FF
  .byte $00,$00,$80,$80,$C0,$C0,$C0,$C0
  .byte $03,$03,$03,$03,$01,$01,$00,$00
  .byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$7F
  .byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FE
  .byte $C0,$C0,$C0,$C0,$80,$80,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $3F,$0F,$00,$00,$00,$00,$00,$00
  .byte $FC,$F0,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$01
  .byte $00,$00,$00,$00,$1F,$7F,$FF,$FF
  .byte $00,$00,$00,$00,$F8,$FE,$FF,$FF
  .byte $00,$00,$00,$00,$00,$00,$00,$80
  .byte $03,$07,$07,$0F,$0F,$0F,$0F,$0F
  .byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
  .byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
  .byte $C0,$E0,$E0,$F0,$F0,$F0,$F0,$F0
  .byte $0F,$0F,$0F,$0F,$0F,$07,$07,$03
  .byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
  .byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
  .byte $F0,$F0,$F0,$F0,$F0,$E0,$E0,$C0
  .byte $01,$00,$00,$00,$00,$00,$00,$00
  .byte $FF,$FF,$7F,$1F,$00,$00,$00,$00
  .byte $FF,$FF,$FE,$F8,$00,$00,$00,$00
  .byte $80,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$01,$03,$07,$0F
  .byte $00,$00,$1F,$7F,$FF,$FF,$FF,$FF
  .byte $00,$00,$F8,$FE,$FF,$FF,$FF,$FF
  .byte $00,$00,$00,$00,$80,$C0,$E0,$F0
  .byte $0F,$1F,$1F,$3F,$3F,$3F,$3F,$3F
  .byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
  .byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
  .byte $F0,$F8,$F8,$FC,$FC,$FC,$FC,$FC
  .byte $3F,$3F,$3F,$3F,$3F,$1F,$1F,$0F
  .byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
  .byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
  .byte $FC,$FC,$FC,$FC,$FC,$F8,$F8,$F0
  .byte $0F,$07,$03,$01,$00,$00,$00,$00
  .byte $FF,$FF,$FF,$FF,$7F,$1F,$00,$00
  .byte $FF,$FF,$FF,$FF,$FE,$F8,$00,$00
  .byte $F0,$E0,$C0,$80,$00,$00,$00,$00
  .byte $00,$00,$01,$03,$07,$0F,$1F,$3F
  .byte $0F,$7F,$FF,$FF,$FF,$FF,$FF,$FF
  .byte $F0,$FE,$FF,$FF,$FF,$FF,$FF,$FF
  .byte $00,$00,$80,$C0,$E0,$F0,$F8,$FC
  .byte $3F,$7F,$7F,$7F,$FF,$FF,$FF,$FF
  .byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
  .byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
  .byte $FC,$FE,$FE,$FE,$FF,$FF,$FF,$FF
  .byte $FF,$FF,$FF,$FF,$7F,$7F,$7F,$3F
  .byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
  .byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
  .byte $FF,$FF,$FF,$FF,$FE,$FE,$FE,$FC
  .byte $3F,$1F,$0F,$07,$03,$01,$00,$00
  .byte $FF,$FF,$FF,$FF,$FF,$FF,$7F,$0F
  .byte $FF,$FF,$FF,$FF,$FF,$FF,$FE,$F0
  .byte $FC,$F8,$F0,$E0,$C0,$80,$00,$00
; raggio di collisione (pixel) per ogni forma
EXPL_RAD:
  .byte $02,$04,$06,$08,$0A,$0C,$0E,$10
; sequenza delle forme (cresce, tiene, cala)
EXPL_SEQ:
  .byte $00,$01,$02,$03,$04,$05,$06,$07,$07,$07,$06,$05,$04,$03,$02,$01,$00
SEQ_LEN = 17
; per ondata: n. testate, max contemporanee, ritardo tra lanci (frame), velocita' (frazione 8 bit di pixel/frame)
WAVE_N:
  .byte $0A,$0C,$0E,$10,$12,$14,$16,$18,$1A,$1C,$1E,$1E,$1E,$1E,$1E
WAVE_MAX:
  .byte $03,$03,$04,$04,$05,$05,$06,$06,$07,$07,$08,$08,$08,$08,$08
WAVE_DLY:
  .byte $42,$3E,$3A,$36,$32,$2E,$2A,$26,$22,$1E,$1A,$18,$18,$18,$18
WAVE_SPF:
  .byte $50,$5E,$6C,$7A,$88,$96,$A4,$B2,$C0,$CE,$DC,$EA,$F0,$F0,$F0
; ---- periodi AY (1 MHz): TP = 62500 / f.  indice = nota MIDI - 35 (1 = C2 ... 55 = F#6), 0 = pausa
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
V0_TAB:        .byte 13, 9, 12, 0      ; volume all'attacco della nota (melodia, arpeggio, basso)
FLOOR_TAB:     .byte 9, 4, 8, 0        ; volume minimo raggiunto dal decadimento
DECMASK_TAB:   .byte 7, 3, 3, 0        ; il volume cala di 1 quando (eta' AND maschera) = 0
VIB_TAB:       .byte 0, 1, 1, 0, 0, $FF, $FF, 0   ; vibrato +-1 passo (signed)
; batteria: 1 cassa, 2 rullante, 3 charleston, 4 piatto
DRUM_NP:       .byte 0, 28, 10, 2, 5
DRUM_V0:       .byte 0, 15, 14, 8, 15
DRUM_MASK:     .byte 0, 0, 0, 0, 7
TITLE_LEAD:
  .byte 41,20,41,10,44,10,46,40,42,20,42,10,41,10,37,40
  .byte 39,20,39,10,41,10,44,40,41,20,40,20,41,40,46,120
  .byte 255
TITLE_HARM:
  .byte 22,10,25,10,29,10,25,10,22,10,25,10,29,10,25,10
  .byte 18,10,22,10,25,10,22,10,18,10,22,10,25,10,22,10
  .byte 20,10,24,10,27,10,24,10,20,10,24,10,27,10,24,10
  .byte 17,10,21,10,24,10,21,10,17,10,21,10,24,10,21,10
  .byte 22,10,25,10,29,10,25,10,22,10,25,10,29,10,25,10
  .byte 22,10,25,10,29,10,25,10,255
TITLE_BASS:
  .byte 10,20,10,20,17,20,10,20,6,20,6,20,13,20,6,20
  .byte 8,20,8,20,15,20,8,20,5,20,5,20,12,20,5,20
  .byte 10,120,255
TITLE_DRUM:
  .byte 1,10,3,10,2,10,3,10,1,10,3,10,2,10,3,10
  .byte 1,10,3,10,2,10,3,10,1,10,3,10,2,10,3,10
  .byte 1,10,3,10,2,10,3,10,1,10,3,10,2,10,3,10
  .byte 1,10,3,10,2,10,3,10,1,10,3,10,2,10,3,10
  .byte 4,120,255
LOSE_LEAD:
  .byte 34,28,33,28,32,28,31,28,29,140,255
LOSE_HARM:
  .byte 25,28,24,28,23,28,22,28,20,140,255
LOSE_BASS:
  .byte 10,28,9,28,8,28,7,28,5,140,255
LOSE_DRUM:
  .byte 1,28,0,28,1,28,0,28,4,140,255
SONGP_LO:      .byte <TITLE_LEAD,<TITLE_HARM,<TITLE_BASS,<TITLE_DRUM,<LOSE_LEAD,<LOSE_HARM,<LOSE_BASS,<LOSE_DRUM
SONGP_HI:      .byte >TITLE_LEAD,>TITLE_HARM,>TITLE_BASS,>TITLE_DRUM,>LOSE_LEAD,>LOSE_HARM,>LOSE_BASS,>LOSE_DRUM
; fischi (id 1-7): per ogni frame periodo del tono e volume
WH_TL:
  .byte $60,$5C,$58,$54,$51,$4D,$4A,$47,$44,$41,$3E,$3C,$39,$37,$34,$32
  .byte $30,$2E,$2C,$2A,$28,$27,$25,$23,$22,$20,$1F,$1E,$1C,$1B,$39,$36
  .byte $33,$30,$2D,$2B,$28,$26,$24,$22,$20,$1F,$1D,$1B,$1A,$18,$17,$16
  .byte $15,$13,$12,$11,$17,$18,$18,$1A,$1A,$1B,$1B,$1C,$1E,$1F,$1F,$20
  .byte $21,$23,$24,$24,$25,$27,$28,$29,$2A,$2B,$2D,$2F,$30,$30,$32,$34
  .byte $36,$37,$38,$3A,$3D,$3F,$40,$41,$44,$47,$49,$4A,$4C,$4F,$53,$55
  .byte $56,$58,$2A,$2A,$2A,$19,$19,$19,$2A,$2A,$2A,$19,$19,$19,$2A,$2A
  .byte $2A,$19,$19,$19,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$A1,$78,$78,$78,$78
  .byte $78,$78,$78,$78,$5F,$5F,$5F,$5F,$5F,$5F,$5F,$5F,$50,$50,$50,$50
  .byte $50,$50,$50,$50,$50,$50,$78,$78,$78,$78,$78,$5F,$5F,$5F,$5F,$5F
  .byte $50,$50,$50,$50,$50,$3C,$3C,$3C,$3C,$3C,$3C,$3C,$3C,$3C,$3C,$3C
  .byte $3C,$3C,$3C,$3C,$45,$3F,$3D,$3E,$3B,$35,$31,$30,$30,$2E,$29,$26
  .byte $26,$26,$23,$1F,$1D,$1D,$1D,$1B,$18,$17,$17,$17,$1C,$20,$24,$28
  .byte $2D,$32,$38,$3E,$14,$14,$15,$16,$17,$18,$50,$50,$50,$50,$3F,$3F
  .byte $3F,$3F,$2F,$2F,$2F,$2F,$2F,$2F,$2F,$2F
WH_TH:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$01,$01,$01,$01,$01,$01,$01,$01,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00
WH_VOL:
  .byte $0B,$0B,$0B,$0B,$0B,$0A,$0A,$0A,$0A,$0A,$0A,$0A,$0A,$0A,$0A,$09
  .byte $09,$09,$09,$09,$09,$09,$09,$09,$09,$08,$08,$06,$04,$02,$0C,$0C
  .byte $0C,$0C,$0B,$0B,$0B,$0B,$0B,$0B,$0B,$0A,$0A,$0A,$0A,$0A,$0A,$0A
  .byte $09,$07,$05,$02,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06
  .byte $06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$05,$05,$05,$05,$05
  .byte $05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$05,$04,$04,$03,$02
  .byte $01,$01,$09,$09,$09,$09,$09,$09,$09,$09,$09,$09,$09,$09,$09,$09
  .byte $09,$04,$04,$04,$09,$08,$07,$06,$05,$04,$03,$02,$0C,$0C,$0C,$0B
  .byte $0B,$0B,$0A,$0A,$0C,$0C,$0C,$0B,$0B,$0B,$0A,$0A,$0C,$0C,$0C,$0C
  .byte $0B,$0B,$0B,$0A,$0A,$0A,$0C,$0C,$0B,$0B,$0A,$0C,$0C,$0B,$0B,$0A
  .byte $0C,$0C,$0B,$0B,$0A,$0C,$0C,$0C,$0C,$0C,$0B,$0B,$0B,$0B,$0B,$0A
  .byte $0A,$0A,$0A,$0A,$0A,$0A,$0A,$0A,$0A,$0A,$09,$09,$09,$09,$09,$09
  .byte $09,$09,$09,$09,$09,$09,$08,$08,$08,$06,$04,$02,$0A,$09,$09,$08
  .byte $08,$07,$04,$02,$09,$08,$08,$07,$04,$02,$0C,$0C,$0B,$0A,$0C,$0C
  .byte $0B,$0A,$0C,$0C,$0C,$0B,$0B,$0B,$0A,$0A
WH_START:
  .byte $00,$00,$1E,$34,$62,$74,$7C,$96
  .byte $B4,$CC,$D4,$DA
WH_LEN:
  .byte $00,$1E,$16,$2E,$12,$08,$1A,$1E
  .byte $18,$08,$06,$10
W_FIRE_SIDE = 1
W_FIRE_CENTER = 2
W_ENEMY = 3
W_MIRV = 4
W_EMPTY = 5
W_WAVE = 6
W_BONUS = 7
W_FIRE_P2 = 8
W_KILL_PLAIN = 9
W_KILL_CHILD = 10
W_KILL_MIRV = 11
; esplosioni: id 1 piccola (20 frame), id 2 grande (62 frame): rumore B + botto grave C
EX_NV:
  .byte $0F,$0E,$0D,$0C,$0B,$0A,$09,$08,$07,$06,$05,$04,$03,$03,$02,$02
  .byte $01,$01,$00,$00,$0F,$0F,$0F,$0F,$0E,$0E,$0D,$0D,$0C,$0C,$0C,$0C
  .byte $0B,$0B,$0A,$0A,$0A,$0A,$09,$09,$09,$09,$08,$08,$08,$08,$07,$07
  .byte $06,$06,$06,$06,$05,$05,$05,$05,$04,$04,$04,$04,$03,$03,$03,$03
  .byte $03,$03,$02,$02,$02,$02,$01,$01,$01,$01,$01,$01,$00,$00,$00,$00
  .byte $00,$00
EX_NP:
  .byte $04,$05,$06,$07,$08,$09,$0A,$0B,$0C,$0D,$0E,$0F,$10,$11,$12,$13
  .byte $14,$15,$16,$17,$03,$03,$05,$05,$07,$07,$08,$08,$09,$09,$0A,$0A
  .byte $0B,$0B,$0C,$0C,$0D,$0D,$0E,$0E,$0F,$0F,$0F,$0F,$10,$10,$11,$11
  .byte $12,$12,$12,$12,$13,$13,$14,$14,$14,$14,$15,$15,$16,$16,$16,$16
  .byte $17,$17,$18,$18,$18,$18,$19,$19,$1A,$1A,$1A,$1A,$1B,$1B,$1B,$1B
  .byte $1C,$1C
EX_VC:
  .byte $0C,$0C,$0B,$0A,$09,$08,$07,$06,$06,$05,$04,$03,$02,$01,$00,$00
  .byte $00,$00,$00,$00,$0E,$0E,$0D,$0D,$0D,$0D,$0C,$0C,$0C,$0C,$0B,$0B
  .byte $0A,$0A,$0A,$0A,$09,$09,$09,$09,$08,$08,$08,$08,$07,$07,$06,$06
  .byte $06,$06,$05,$05,$05,$05,$04,$04,$04,$04,$03,$03,$02,$02,$02,$02
  .byte $01,$01,$01,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00
EX_TL:
  .byte $08,$26,$44,$62,$80,$9E,$BC,$DA,$F8,$16,$34,$52,$70,$8E,$AC,$CA
  .byte $E8,$06,$24,$42,$C8,$C8,$D6,$D6,$E5,$E5,$F5,$F5,$06,$06,$18,$18
  .byte $2B,$2B,$40,$40,$56,$56,$6E,$6E,$87,$87,$A3,$A3,$C0,$C0,$DF,$DF
  .byte $00,$00,$24,$24,$4A,$4A,$72,$72,$9E,$9E,$CD,$CD,$FE,$FE,$34,$34
  .byte $6C,$6C,$A9,$A9,$EA,$EA,$30,$30,$7B,$7B,$CA,$CA,$1F,$1F,$7B,$7B
  .byte $DC,$DC
EX_TH:
  .byte $02,$02,$02,$02,$02,$02,$02,$02,$02,$03,$03,$03,$03,$03,$03,$03
  .byte $03,$04,$04,$04,$00,$00,$00,$00,$00,$00,$00,$00,$01,$01,$01,$01
  .byte $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
  .byte $02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$02,$03,$03
  .byte $03,$03,$03,$03,$03,$03,$04,$04,$04,$04,$04,$04,$05,$05,$05,$05
  .byte $05,$05
EX_START:      .byte 0,0,20
EX_LEN:        .byte 0,20,62
S_SMALL = 1
S_BIG   = 2
TXT_HUD:
  .byte $00,$01,$0F,$53,$43,$4F,$52,$45,$00   ; "SCORE"
  .byte $00,$15,$0F,$57,$41,$56,$45,$00   ; "WAVE"
  .byte $FF
TXT_TITLE:
  .byte $09,$07,$0B,$44,$45,$46,$45,$4E,$44,$20,$54,$48,$45,$20,$43,$49,$54,$49,$45,$53,$00   ; "DEFEND THE CITIES"
  .byte $0B,$09,$0F,$4A,$4F,$59,$53,$54,$49,$43,$4B,$20,$3D,$20,$41,$49,$4D,$00   ; "JOYSTICK = AIM"
  .byte $0D,$04,$0F,$42,$55,$54,$54,$4F,$4E,$20,$31,$20,$3D,$20,$4E,$45,$41,$52,$45,$53,$54,$20,$42,$41,$53,$45,$00   ; "BUTTON 1 = NEAREST BASE"
  .byte $0F,$05,$0F,$42,$55,$54,$54,$4F,$4E,$20,$32,$20,$3D,$20,$43,$45,$4E,$54,$45,$52,$20,$42,$41,$53,$45,$00   ; "BUTTON 2 = CENTER BASE"
  .byte $11,$04,$07,$46,$4F,$52,$20,$32,$20,$50,$4C,$41,$59,$45,$52,$53,$20,$55,$53,$45,$20,$4A,$4F,$59,$20,$32,$00   ; "FOR 2 PLAYERS USE JOY 2"
  .byte $13,$09,$0E,$50,$52,$45,$53,$53,$20,$41,$20,$42,$55,$54,$54,$4F,$4E,$00   ; "PRESS A BUTTON"
  .byte $FF
TXT_REC:
  .byte $01,$08,$0E,$48,$49,$20,$53,$43,$4F,$52,$45,$00   ; "HI SCORE"
  .byte $FF
TXT_WAVE:
  .byte $09,$0D,$0B,$57,$41,$56,$45,$00   ; "WAVE"
  .byte $FF
TXT_BONUS:
  .byte $06,$0A,$0B,$57,$41,$56,$45,$20,$43,$4C,$45,$41,$52,$45,$44,$00   ; "WAVE CLEARED"
  .byte $08,$07,$0F,$43,$49,$54,$49,$45,$53,$20,$53,$41,$56,$45,$44,$00   ; "CITIES SAVED"
  .byte $0A,$07,$0F,$4D,$49,$53,$53,$49,$4C,$45,$53,$20,$4C,$45,$46,$54,$00   ; "MISSILES LEFT"
  .byte $0C,$07,$09,$42,$4F,$4E,$55,$53,$00   ; "BONUS"
  .byte $FF
TXT_OVER:
  .byte $07,$0B,$09,$47,$41,$4D,$45,$20,$4F,$56,$45,$52,$00   ; "GAME OVER"
  .byte $0A,$09,$0F,$53,$43,$4F,$52,$45,$00   ; "SCORE"
  .byte $0C,$09,$0F,$48,$49,$20,$53,$43,$4F,$52,$45,$00   ; "HI SCORE"
  .byte $0F,$09,$0E,$50,$52,$45,$53,$53,$20,$41,$20,$42,$55,$54,$54,$4F,$4E,$00   ; "PRESS A BUTTON"
  .byte $FF
TITLE_BIG:
  .byte 3,9,7,0,1,2,2,1,3,4   ; MISSILE
  .byte 6,9,7,5,6,0,0,7,8,9   ; COMMAND
  .byte $FF
