;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;                                                              ;
;   ARCADE_003  -  DAVIDE vs ELIA, basket 1 contro 1  + SOUND  ;
;   65C02 assembly, TMS9918A Graphics II                       ;
;   Base: arcade_002 (NMI/vblank + SAT buffer, VDP, joystick)  ;
;                                                              ;
;   - P1 (DAVIDE) su PORTA $D581, attacca il canestro destro   ;
;     P2 (ELIA)   su PORTB $D580, attacca il canestro sinistro ;
;   - joystick = muove; un tasto qualsiasi (bit4 o bit5):      ;
;       con la palla  -> TIRO (salto, la palla parte al vertice)
;       senza palla   -> SALTO: ruba la palla se sei vicino,   ;
;                        o STOPPA il tiro se salti al momento  ;
;                        giusto mentre l'avversario tira       ;
;   - dentro la linea = 2 punti, fuori dall'arco = 3 punti     ;
;   - dopo un canestro la palla passa all'avversario           ;
;   - vince chi arriva a WIN_SCORE (21) punti                  ;
;   - SONORO (2 x AY-3-8910): canzone al titolo, tiro segnato,  ;
;     tiro sbagliato, palleggio, applauso (canestro, stoppata,   ;
;     furto); a fine partita applauso + gridi + canzone         ;
;   - tutta la grafica del campo e' nelle tabelle in fondo     ;
;     (generate: campo, sprite, tabelle di salto e di traiettoria)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; ---------------- zero page (usate per la copia dei blocchi VDP) ----------------
VDP_INIT                 = $30
VDP_INIT_HI              = $31

; ---------------- zero page: dati dei due giocatori ----------------
; ogni voce occupa 2 byte: indice X = 0 (DAVIDE) oppure 1 (ELIA)
P_X                      = $60     ; X sprite (bordo sinistro, sprite largo 16)
P_FY                     = $62     ; Y dei piedi (posizione sul campo)
P_FACE                   = $64     ; 0 = guarda a destra, 1 = a sinistra
P_JOY                    = $66     ; joystick, 1 = premuto
P_OLD                    = $68     ; stato pulsanti al frame precedente
P_EDGE                   = $6A     ; pulsante appena premuto
P_WALK                   = $6C     ; contatore animazione gambe
P_JUMP                   = $6E     ; frame di salto rimasti (0 = a terra)
P_COOL                   = $70     ; attesa dopo il salto
P_SHOT                   = $72     ; 1 = il salto in corso e' un tiro
P_SCORE                  = $74     ; punteggio

; ---------------- zero page: palla e stato di gioco ----------------
HOLDER                   = $76     ; chi ha la palla (valido se BSTATE = 0)
BSTATE                   = $77     ; 0 = in mano, 1 = tiro in volo, 2 = libera, 3 = nella retina
B_T                      = $78     ; contatore frame della fase
B_PTS                    = $79     ; punti del tiro in volo (2 o 3)
B_MAKE                   = $7A     ; 1 = il tiro va a canestro
SHOOTER                  = $7B     ; chi ha tirato
B_GXL                    = $7C     ; posizione a terra della palla, 8.8
B_GXH                    = $7D
B_GYL                    = $7E
B_GYH                    = $7F
B_VXL                    = $80     ; velocita' per frame, 8.8 con segno
B_VXH                    = $81
B_VYL                    = $82
B_VYH                    = $83
B_H                      = $84     ; altezza della palla da terra (pixel)
FREEZE                   = $85     ; frame di pausa (dopo canestro / inizio)
RND                      = $86
MSG_NEW                  = $87     ; messaggio da scrivere ($FF = nessuno)
MSG_TMR                  = $88
HUD_DIRTY                = $89
WINNER                   = $8A
ARMED                    = $8B
GO_DELAY                 = $8C
DRB                      = $8D     ; fase del palleggio
T0                       = $90
T1                       = $91
T2                       = $92
T3                       = $93
T4                       = $94
T5                       = $95
T6                       = $96
T7                       = $97
PTR                      = $98     ; 2 byte

PORTB_JOY = $d580        ;         |P2|P1|RG|LF|DW|UP (LSB)   joystick 2
PORTA_JOY = $d581        ;         |P2|P1|RG|LF|DW|UP (LSB)   joystick 1
DDRB_JOY  = $d582        ;
DDRA_JOY  = $d583        ;

; ---------------- parametri di gioco ----------------
WIN_SCORE     = 21       ; punti per vincere
SPEED_X       = 2        ; pixel per frame in orizzontale
SPEED_Y       = 1        ; pixel per frame in verticale (prospettiva)
JUMP_LEN      = 24       ; durata del salto (frame)
RELEASE_AT    = 12       ; la palla parte quando mancano 12 frame (vertice del salto)
COOL_LEN      = 12       ; attesa dopo un salto
BLOCK_LO      = 5        ; finestra di salto del difensore che stoppa il tiro:
BLOCK_HI      = 19       ;   P_JUMP del difensore compreso tra BLOCK_LO e BLOCK_HI
CONTEST_DX    = 26       ; difensore "addosso": distanza massima in X ...
CONTEST_DY    = 14       ; ... e in Y
CONTEST_PEN   = 50       ; penalita' sulla probabilita' se il tiro e' contrastato
STEAL_DX      = 18       ; furto: distanza massima
STEAL_DY      = 10
STEAL_PROB    = 128      ; probabilita' di rubare (su 256)
PROB_KEY      = 200      ; probabilita' di segnare: sotto canestro (area)
PROB_MID      = 150      ;   da dentro l'arco (2 punti)
PROB_FAR      = 100      ;   da fuori dall'arco (3 punti)
FY_MIN        = 64       ; limiti verticali (piedi)
FY_MAX        = 188
RIM_GY        = 105      ; riga a terra sotto il ferro (ferro = 72, altezza 30, raggio palla 3)
H_START       = 36       ; altezza della palla al tiro
BLOCK_AWAY    = 22       ; di quanto rimbalza all'indietro una palla stoppata
RIM_BACK      = 18       ; rimbalzo sul ferro: distanza minima dal canestro
FREEZE_FRAMES = 50
MSG_FRAMES    = 90
HIDE_Y        = $C0      ; Y fuori schermo (NON $D0: fermerebbe la lista sprite)
BTN_MASK      = %00110000

D_START_X     = 92       ; posizioni di partenza (Davide a sinistra, Elia a destra)
D_START_Y     = 118
E_START_X     = 132
E_START_Y     = 126

; messaggi (indice nella tabella MSG_TAB)
MSG_P_DAVIDE  = 1
MSG_P_ELIA    = 2
MSG_2         = 3
MSG_3         = 4
MSG_BLOCK     = 5
MSG_STEAL     = 6

; nomi degli sprite (pattern = indice * 4)
SPR_TOP_IDLE  = 8
SPR_TOP_SHOOT = 12
SPR_TOP_DEF   = 16
SPR_BOT_A     = 32
SPR_BOT_B     = 36
SPR_BOT_JUMP  = 40
SPR_LEFT_ADD  = 12       ; i frame verso sinistra sono 12 pattern piu' avanti

BLOCK_COUNT   = 7        ; blocchi in VDP_BLOCKS
BIG0          = $80      ; cifre grandi 0-9: 4 tile ciascuna (alto-sx, alto-dx, basso-sx, basso-dx)


; ---------------- sonoro: porte dei due AY-3-8910 (come tank_sound.asm) ----------------
AY_R_LATCH = $D380       ; AY destro  (Elia)
AY_R_WRITE = $D381
AY_L_LATCH = $D384       ; AY sinistro (Davide)
AY_L_WRITE = $D385

; ---------------- zero page: sonoro (tutto suonato da SND_TICK, chiamata dall'NMI) ----------------
SH_L       = $A0         ; shadow registri AY sinistro 0-10  (11 byte)
SH_R       = $B0         ; shadow registri AY destro   0-10  (SH_R = SH_L + 16)
SND_STAGE  = $BB         ; finale: 0 = applauso, 1 = gridi
SND_T2     = $BC         ; finale: frame trascorsi nella fase
SND_CMD    = $C0         ; comando al motore sonoro (CMD_*), eseguito dall'NMI
SND_MODE   = $C1         ; 0 = effetti di gioco, 1 = canzone, 2 = applauso + gridi finali
SND_BUSY   = $C2         ; 1 finche' la canzone (o il finale) sta suonando
SFX_REQ    = $C3         ; richiesta di effetto (EVT_*), 0 = nessuna
SFX_EVT    = $C4         ; effetto in corso (0 = nessuno)
SFX_STEP   = $C5         ; frame trascorsi nell'effetto
SFX_DRIB   = $C6         ; palleggio: 2 byte (Davide / Elia), passo 1..6 (0 = spento)
SND_PH     = $C8         ; fase (conta i frame)
SND_RND    = $C9
SN0        = $CA         ; temporanei del sonoro
SN1        = $CB
SND_T1     = $CC
SFX_APPL   = $CD         ; applauso: frame trascorsi (0 = spento)
SFX_ADLY   = $CE         ; frame che mancano all'inizio dell'applauso
TR_PL      = $D0         ; 4 tracce: puntatore (lo / hi), contatore, attiva,
TR_PH      = $D4         ;           nota, volume, eta' della nota
TR_CT      = $D8
TR_ACT     = $DC
TR_NOTE    = $E0
TR_VOL     = $E4
TR_AGE     = $E8
SND_PTR    = $EC         ; 2 byte

CMD_GAME   = 1           ; silenzio + effetti di gioco
CMD_TITLE  = 2           ; canzone del titolo
CMD_WIN    = 3           ; applauso + gridi + canzone di vittoria

EVT_SCORE  = 1           ; tiro segnato (+ applauso)
EVT_MISS   = 2           ; tiro sbagliato (ferro)
EVT_BLOCK  = 3           ; stoppata (+ applauso)
EVT_STEAL  = 4           ; palla rubata (+ applauso)

APPL_LEN       = 96      ; durata dell'applauso in partita (frame)
CELEB_APPL_LEN = 150     ; applauso finale (frame)
CHEER_LEN      = 112     ; gridi finali (frame)
DRIB_LEN       = 6       ; durata del tonfo del palleggio (frame)

 .org $0FD0               ; trampolino chiamato da NMI_HANDLER (bios) con JSR $0FD0
DISPATCH:
  JMP NMI_TASK


 .org $1000
VREG  = $B001                ;VDP REGISTER
VDATA = $B000                ;VDP RAM

VDP_NAME_TABLE_BASE    = $3800      ; NAME TABLE
VDP_COLOR_TABLE_BASE   = $2000      ; COLOR TABLE
VDP_PATTERN_TABLE_BASE = $0000      ; PATTERN TABLE
VDP_SPRITE_ATT_BASE    = $3B00      ; SPRITE ATT
VDP_SPRITE_TABLE_BASE  = $1800      ; SPRITE TABLE

VDP_WRITE_VRAM_BIT     = %01000000  ; pattern of second vram address write: 01AAAAAA
VDP_REGISTER_BITS      = %10000000  ; pattern of second register write: 10000RRR

RESET:
  JSR VDP_SET_REGISTERS        ; Setting VDP register
  JSR CLEAR_VRAM
  JSR VDP_LOAD_ALL             ; pattern, colori e sprite nella VRAM

  ; joystick: PORTA e PORTB in input
  LDA #$00
  STA DDRA_JOY
  STA DDRB_JOY

  LDA #$00
  STA P_SCORE
  STA P_SCORE+1
  STA HUD_DIRTY
  STA FREEZE
  LDA #$A5
  STA RND
  JSR HIDE_SPRITES

  JSR SND_INIT                 ; AY a zero (l'interrupt VDP e' ancora spento)

  ; abilita l'interrupt del VDP (R1: 16K + display ON + INT ON = $E6)
  LDA #$E6
  STA VREG
  LDA #(VDP_REGISTER_BITS | 1)
  STA VREG
  JMP TITLE


; ===============================================================
;  SCHERMATA START
; ===============================================================
TITLE:
  LDX #$FF
  TXS                          ; da qui non si torna indietro: stack pulito
  JSR HIDE_SPRITES
  JSR VDP_INT_OFF              ; da ora il main loop puo' scrivere sul VDP
  JSR CLEAR_NAME_TABLE
  LDA #<TITLE_REC
  STA PTR
  LDA #>TITLE_REC
  STA PTR+1
  JSR DRAW_RECORDS
  JSR VDP_INT_ON
  LDA #$01                     ; parte la canzone del titolo ...
  STA SND_BUSY
  LDA #CMD_TITLE
  STA SND_CMD
.ti_song:
  JSR WAIT_FRAME               ; ... il tasto non viene letto finche' suona
  LDA SND_BUSY
  BNE .ti_song
  JSR VDP_INT_OFF
  LDA #<TITLE_PRESS
  STA PTR
  LDA #>TITLE_PRESS
  STA PTR+1
  JSR DRAW_RECORDS             ; compare "PRESS A BUTTON"
  JSR VDP_INT_ON
  JSR WAIT_FIRE
  LDA FRAME_CNT                ; il momento in cui premi il tasto semina il caso
  ORA #$01
  STA RND
  JMP NEW_GAME


; ===============================================================
;  NUOVA PARTITA
; ===============================================================
NEW_GAME:
  LDA #CMD_GAME                ; silenzio, effetti di gioco
  STA SND_CMD
  LDA #$00
  STA P_SCORE
  STA P_SCORE+1
  STA HUD_DIRTY
  STA MSG_TMR
  STA P_OLD
  STA P_OLD+1
  STA DRB
  LDA #$FF
  STA MSG_NEW
  JSR HIDE_SPRITES
  JSR VDP_INT_OFF
  JSR LOAD_GAME_NAME_TABLE     ; campo + nomi
  JSR DRAW_HUD                 ; punteggi grandi a fianco dei nomi
  JSR VDP_INT_ON
  JSR NEXT_RND                 ; il primo possesso e' a caso
  LDA RND
  AND #$01
  JSR START_POSS
  JSR DRAW_ALL

GAME_LOOP:
  JSR READ_JOY
  LDA FREEZE
  BEQ .gl_active
  DEC FREEZE                   ; pausa: tutto fermo, solo il palleggio
  LDA P_JOY
  AND #BTN_MASK
  STA P_OLD
  LDA P_JOY+1
  AND #BTN_MASK
  STA P_OLD+1
  JSR UPDATE_BALL
  BRA .gl_draw
.gl_active:
  JSR NEXT_RND
  LDX #0
  JSR UPDATE_PLAYER
  LDX #1
  JSR UPDATE_PLAYER
  JSR UPDATE_BALL
.gl_draw:
  JSR DRAW_ALL
  JSR WAIT_FRAME               ; sincronizza il loop al vblank (NMI)
  LDA HUD_DIRTY
  BEQ .gl_msg
  LDA #$00
  STA HUD_DIRTY
  JSR UPDATE_HUD
.gl_msg:
  LDA MSG_TMR
  BEQ .gl_pend
  DEC MSG_TMR
  BNE .gl_pend
  LDA #$00                     ; tempo scaduto: cancella il messaggio
  STA MSG_NEW
.gl_pend:
  LDA MSG_NEW
  CMP #$FF
  BEQ .gl_again
  JSR DRAW_MSG
  LDA #$FF
  STA MSG_NEW
.gl_again:
  JMP GAME_LOOP


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
; inizio possesso: A = chi ha la palla (0 = Davide, 1 = Elia).
; Rimette i giocatori in posizione: Davide attacca a destra, quindi
; il suo difensore (Elia) sta alla sua destra; e viceversa.
; ---------------------------------------------------------------
START_POSS:
  STA HOLDER
  LDA #$00
  STA BSTATE
  STA P_JUMP
  STA P_JUMP+1
  STA P_COOL
  STA P_COOL+1
  STA P_SHOT
  STA P_SHOT+1
  STA P_WALK
  STA P_WALK+1
  STA P_FACE                   ; Davide guarda a destra
  LDA #$01
  STA P_FACE+1                 ; Elia guarda a sinistra
  LDA #D_START_X
  STA P_X
  LDA #D_START_Y
  STA P_FY
  LDA #E_START_X
  STA P_X+1
  LDA #E_START_Y
  STA P_FY+1
  LDA #FREEZE_FRAMES
  STA FREEZE
  LDA HOLDER
  CLC
  ADC #MSG_P_DAVIDE            ; 1 = PALLA A DAVIDE, 2 = PALLA A ELIA
  JMP SHOW_MSG

SHOW_MSG:                      ; A = indice messaggio
  STA MSG_NEW
  LDA #MSG_FRAMES
  STA MSG_TMR
  RTS


; ---------------------------------------------------------------
; distanza tra il giocatore X e l'altro: T0 = |dx|, T1 = |dy|  (X preservato)
; ---------------------------------------------------------------
DIST_OTHER:
  LDA P_X,X
  STA T2
  LDA P_FY,X
  STA T3
  TXA
  EOR #$01
  TAX
  LDA P_X,X
  SEC
  SBC T2
  BCS .do_x
  EOR #$FF
  CLC
  ADC #$01
.do_x:
  STA T0
  LDA P_FY,X
  SEC
  SBC T3
  BCS .do_y
  EOR #$FF
  CLC
  ADC #$01
.do_y:
  STA T1
  TXA
  EOR #$01
  TAX
  RTS

; distanza tra il piede del giocatore X e la palla: T0 = |dx|, T1 = |dy|
DIST_BALL:
  LDA P_X,X
  CLC
  ADC #8                       ; centro dello sprite
  SEC
  SBC B_GXH
  BCS .db_x
  EOR #$FF
  CLC
  ADC #$01
.db_x:
  STA T0
  LDA P_FY,X
  SEC
  SBC B_GYH
  BCS .db_y
  EOR #$FF
  CLC
  ADC #$01
.db_y:
  STA T1
  RTS


; ---------------------------------------------------------------
; aggiorna un giocatore: X = giocatore (0/1)
; ---------------------------------------------------------------
UPDATE_PLAYER:
  LDA P_JOY,X                  ; fronte di salita del pulsante
  AND #BTN_MASK
  STA T0
  LDA P_OLD,X
  EOR #$FF
  AND T0
  STA P_EDGE,X
  LDA T0
  STA P_OLD,X
  LDA P_COOL,X
  BEQ .up_nocool
  DEC P_COOL,X
.up_nocool:
  LDA P_JUMP,X
  BEQ .up_ground
  ; ---- in aria: nessun movimento, il salto avanza ----
  DEC P_JUMP,X
  BNE .up_air
  LDA #COOL_LEN
  STA P_COOL,X
  LDA #$00
  STA P_SHOT,X
  RTS
.up_air:
  LDA P_SHOT,X
  BEQ .up_end
  LDA P_JUMP,X
  CMP #RELEASE_AT
  BNE .up_end
  JMP SHOT_RELEASE             ; vertice del salto: la palla parte
.up_end:
  RTS
.up_ground:
  LDA P_EDGE,X
  BEQ .up_move
  LDA P_COOL,X
  BNE .up_move
  JMP START_ACTION             ; tiro o salto
.up_move:
  LDA P_JOY,X
  AND #%00001111
  BNE .up_dirs
  LDA #$00
  STA P_WALK,X                 ; fermo: gambe in posizione base
  RTS
.up_dirs:
  LDA P_JOY,X
  AND #%00001000               ; destra
  BEQ .up_nr
  LDA P_X,X
  CLC
  ADC #SPEED_X
  STA P_X,X
  LDA #$00
  STA P_FACE,X
.up_nr:
  LDA P_JOY,X
  AND #%00000100               ; sinistra
  BEQ .up_nl
  LDA P_X,X
  SEC
  SBC #SPEED_X
  STA P_X,X
  LDA #$01
  STA P_FACE,X
.up_nl:
  LDA P_JOY,X
  AND #%00000001               ; su
  BEQ .up_nu
  LDA P_FY,X
  SEC
  SBC #SPEED_Y
  STA P_FY,X
.up_nu:
  LDA P_JOY,X
  AND #%00000010               ; giu'
  BEQ .up_nd
  LDA P_FY,X
  CLC
  ADC #SPEED_Y
  STA P_FY,X
.up_nd:
  INC P_WALK,X
  ; ---- limiti del campo (trapezio: i lati sono inclinati) ----
  LDA P_FY,X
  CMP #FY_MIN
  BCS .up_c1
  LDA #FY_MIN
  STA P_FY,X
.up_c1:
  CMP #(FY_MAX+1)
  BCC .up_c2
  LDA #FY_MAX
  STA P_FY,X
.up_c2:
  LDA P_FY,X
  SEC
  SBC #FY_MIN
  TAY
  LDA XMIN_TAB,Y
  STA T0
  LDA P_X,X
  CMP T0
  BCS .up_c3
  LDA T0
  STA P_X,X
.up_c3:
  LDA #240
  SEC
  SBC T0                       ; XMAX = 240 - XMIN
  STA T0
  LDA P_X,X
  CMP T0
  BCC .up_c4
  BEQ .up_c4
  LDA T0
  STA P_X,X
.up_c4:
  RTS


; ---------------------------------------------------------------
; pulsante premuto a terra: X = giocatore
;   con la palla -> inizia il tiro; senza -> salto (furto / stoppata)
; ---------------------------------------------------------------
START_ACTION:
  LDA #JUMP_LEN
  STA P_JUMP,X
  LDA BSTATE
  BNE .sa_def
  CPX HOLDER
  BNE .sa_def
  LDA #$01                     ; tiro
  STA P_SHOT,X
  TXA                          ; si gira verso il suo canestro: Davide (0) a destra, Elia (1) a sinistra
  STA P_FACE,X
  RTS
.sa_def:
  LDA #$00
  STA P_SHOT,X
  LDA BSTATE
  BNE .sa_end                  ; palla non in mano a nessuno
  TXA
  EOR #$01
  TAX                          ; X = chi ha la palla
  LDA P_SHOT,X
  STA T7                       ; sta gia' tirando? (palla alzata, non rubabile)
  TXA
  EOR #$01
  TAX                          ; X = difensore
  LDA T7
  BNE .sa_end
  JSR DIST_OTHER
  LDA T0
  CMP #STEAL_DX
  BCS .sa_end
  LDA T1
  CMP #STEAL_DY
  BCS .sa_end
  JSR NEXT_RND
  LDA RND
  CMP #STEAL_PROB
  BCS .sa_end
  STX HOLDER                   ; palla rubata
  LDA #MSG_STEAL
  JSR SHOW_MSG
  LDA #EVT_STEAL               ; suono + applauso
  STA SFX_REQ
.sa_end:
  RTS


; ---------------------------------------------------------------
; zona di tiro del giocatore X: A = probabilita' (0-255), B_PTS = 2 o 3
; usa T0-T3.  Il giocatore 0 attacca a destra, il giocatore 1 a sinistra.
; L'arco e' un'ellisse (ARCDX_TAB[dy] = semiasse in X alla distanza dy
; dal centro dell'arco); l'area e' dx < 54 e dy < 20.
; ---------------------------------------------------------------
CALC_ZONE:
  LDA P_X,X
  CLC
  ADC #8
  STA T2                       ; X del centro dei piedi
  CPX #$00
  BNE .cz_left
  LDA #251                     ; arco di destra: centro a 255-4
  SEC
  SBC T2
  BRA .cz_dx
.cz_left:
  LDA T2
  SEC
  SBC #4                       ; arco di sinistra: centro a 4
.cz_dx:
  STA T0                       ; distanza dal centro dell'arco in X
  LDA P_FY,X
  SEC
  SBC #127                     ; centro verticale dell'arco
  BCS .cz_dy
  EOR #$FF
  CLC
  ADC #$01
.cz_dy:
  STA T1
  LDA T0                       ; area
  CMP #54
  BCS .cz_notkey
  LDA T1
  CMP #20
  BCS .cz_notkey
  LDA #$02
  STA B_PTS
  LDA #PROB_KEY
  RTS
.cz_notkey:
  LDA T1
  CMP #63
  BCS .cz_three
  TAY
  LDA ARCDX_TAB,Y
  CMP T0
  BCS .cz_two                  ; dentro l'ellisse
.cz_three:
  LDA #$03
  STA B_PTS
  LDA #PROB_FAR
  RTS
.cz_two:
  LDA #$02
  STA B_PTS
  LDA #PROB_MID
  RTS


; (T4 - T5) << T6  ->  T1:T0  (16 bit con segno; T6 = 3 o 4)
VEL_CALC:
  LDA T4
  SEC
  SBC T5
  STA T0
  LDA #$00
  SBC #$00
  STA T1
  LDY T6
.vc_sh:
  ASL T0
  ROL T1
  DEY
  BNE .vc_sh
  RTS


; ---------------------------------------------------------------
; vertice del salto: la palla parte.  X = tiratore
; ---------------------------------------------------------------
SHOT_RELEASE:
  LDA #$00
  STA P_SHOT,X
  STA T6                       ; T6 = 1 se il tiro e' contrastato
  JSR DIST_OTHER               ; T0/T1 = distanza dal difensore
  LDA T0
  CMP #CONTEST_DX
  BCS .sr_free
  LDA T1
  CMP #CONTEST_DY
  BCS .sr_free
  LDA #$01
  STA T6
  TXA                          ; il difensore e' in salto al momento giusto?
  EOR #$01
  TAX
  LDA P_JUMP,X
  STA T7
  TXA
  EOR #$01
  TAX
  LDA T7
  CMP #BLOCK_LO
  BCC .sr_free
  CMP #(BLOCK_HI+1)
  BCS .sr_free
  JMP BLOCK_SHOT               ; STOPPATA
.sr_free:
  JSR CALC_ZONE                ; B_PTS e probabilita' base
  STA T7
  LDA T6
  BEQ .sr_roll
  LDA T7                       ; contrastato: meno probabilita'
  SEC
  SBC #CONTEST_PEN
  BCS .sr_pen
  LDA #$00
.sr_pen:
  STA T7
.sr_roll:
  JSR NEXT_RND
  LDA RND
  CMP T7
  LDA #$00
  BCS .sr_set                  ; caso >= probabilita': sbaglia
  LDA #$01
.sr_set:
  STA B_MAKE
  STX SHOOTER
  LDA #$01
  STA BSTATE
  LDA #$00
  STA B_T
  STA B_GXL
  STA B_GYL
  LDA P_X,X
  CLC
  ADC #8
  STA B_GXH
  STA T5
  LDA HOOPX,X
  STA T4
  LDA #$03
  STA T6
  JSR VEL_CALC                 ; 32 frame di volo: velocita' = differenza * 8 (in 8.8)
  LDA T0
  STA B_VXL
  LDA T1
  STA B_VXH
  LDA P_FY,X
  STA B_GYH
  STA T5
  LDA #RIM_GY
  STA T4
  JSR VEL_CALC
  LDA T0
  STA B_VYL
  LDA T1
  STA B_VYH
  LDA #H_START
  STA B_H
  RTS


; tiro stoppato: la palla torna indietro e diventa libera. X = tiratore
BLOCK_SHOT:
  STX SHOOTER
  LDA #$02
  STA BSTATE
  LDA #$00
  STA B_T
  STA B_GXL
  STA B_GYL
  LDA P_X,X
  CLC
  ADC #8
  STA B_GXH
  STA T5
  CPX #$00
  BNE .bl_l
  LDA T5
  CMP #(16+BLOCK_AWAY)
  BCC .bl_min
  SEC
  SBC #BLOCK_AWAY
  BRA .bl_x
.bl_min:
  LDA #16
  BRA .bl_x
.bl_l:
  LDA T5
  CMP #(240-BLOCK_AWAY)
  BCS .bl_max
  CLC
  ADC #BLOCK_AWAY
  BRA .bl_x
.bl_max:
  LDA #239
.bl_x:
  STA T4
  LDA #$04
  STA T6
  JSR VEL_CALC                 ; 16 frame: velocita' = differenza * 16
  LDA T0
  STA B_VXL
  LDA T1
  STA B_VXH
  LDA P_FY,X
  STA B_GYH
  LDA #$00
  STA B_VYL
  STA B_VYH
  LDA #30
  STA B_H
  LDA #EVT_BLOCK               ; suono + applauso
  STA SFX_REQ
  LDA #MSG_BLOCK
  JMP SHOW_MSG


; ---------------------------------------------------------------
; la palla: UPDATE_BALL in base a BSTATE
; ---------------------------------------------------------------
UPDATE_BALL:
  LDA BSTATE
  BEQ .ub_held
  CMP #$01
  BEQ .ub_flight
  CMP #$02
  BEQ .ub_loose
  JMP .ub_net
.ub_held:
  LDX HOLDER
  LDA P_X,X
  CLC
  ADC #8
  STA T0
  LDA P_FACE,X
  BNE .ub_hl
  LDA T0
  CLC
  ADC #10
  BRA .ub_hx
.ub_hl:
  LDA T0
  SEC
  SBC #10
.ub_hx:
  STA B_GXH
  LDA P_FY,X
  CLC
  ADC #2
  STA B_GYH
  LDA P_JUMP,X
  BEQ .ub_dribble
  TAY                          ; in salto: la palla e' sopra la testa
  LDA JUMP_H,Y
  CLC
  ADC #H_START
  STA B_H
  RTS
.ub_dribble:
  INC DRB
  LDA DRB
  AND #$0F
  TAY
  LDA DRIB_TAB,Y
  STA B_H
  CPY #8                       ; la palla tocca terra: tonfo sul chip di chi palleggia
  BNE .ub_dr_end
  LDA #$01
  STA SFX_DRIB,X
.ub_dr_end:
  RTS

.ub_flight:
  JSR MOVE_BALL
  INC B_T
  LDY B_T
  LDA HT_TAB,Y
  STA B_H
  CPY #32
  BNE .ub_fl_end
  JSR SHOT_END
.ub_fl_end:
  RTS

.ub_loose:
  LDA B_T
  CMP #16
  BCS .ub_rest
  JSR MOVE_BALL
  INC B_T
  LDY B_T
  LDA BNC_TAB,Y
  STA B_H
  BRA .ub_pick
.ub_rest:
  LDA #$00
  STA B_H
.ub_pick:
  LDA B_T                      ; la palla si raccoglie solo quando e' bassa
  CMP #9
  BCC .ub_pk_end
  LDX #$00
.ub_pk:
  LDA P_JUMP,X
  BNE .ub_pk_next
  JSR DIST_BALL
  LDA T0
  CMP #12
  BCS .ub_pk_next
  LDA T1
  CMP #9
  BCS .ub_pk_next
  STX HOLDER                   ; palla raccolta
  LDA #$00
  STA BSTATE
  RTS
.ub_pk_next:
  INX
  CPX #$02
  BNE .ub_pk
.ub_pk_end:
  RTS

.ub_net:                       ; la palla cade nella retina
  INC B_T
  LDY B_T
  LDA NET_TAB,Y
  STA B_H
  CPY #12
  BNE .ub_net_end
  LDX SHOOTER                  ; fine azione: vittoria o nuovo possesso
  LDA P_SCORE,X
  CMP #WIN_SCORE
  BCC .ub_next
  STX WINNER
  JMP GAME_OVER
.ub_next:
  TXA
  EOR #$01
  JMP START_POSS               ; la palla passa all'avversario
.ub_net_end:
  RTS

; posizione a terra += velocita' (16 bit con segno, 8.8)
MOVE_BALL:
  LDA B_GXL
  CLC
  ADC B_VXL
  STA B_GXL
  LDA B_GXH
  ADC B_VXH
  STA B_GXH
  LDA B_GYL
  CLC
  ADC B_VYL
  STA B_GYL
  LDA B_GYH
  ADC B_VYH
  STA B_GYH
  RTS

; il tiro e' arrivato al ferro
SHOT_END:
  LDA B_MAKE
  BEQ .se_miss
  LDX SHOOTER                  ; canestro!
  LDA P_SCORE,X
  CLC
  ADC B_PTS
  STA P_SCORE,X
  LDA #$01
  STA HUD_DIRTY
  LDA B_PTS
  CMP #$03
  BEQ .se_3
  LDA #MSG_2
  BRA .se_m
.se_3:
  LDA #MSG_3
.se_m:
  JSR SHOW_MSG
  LDA #EVT_SCORE               ; retina + chime + applauso
  STA SFX_REQ
  LDA #$03
  STA BSTATE
  LDA #$00
  STA B_T
  RTS
.se_miss:                      ; sbaglia: rimbalza sul ferro e la palla e' libera
  LDA #EVT_MISS                ; il ferro
  STA SFX_REQ
  LDX SHOOTER
  LDA #$02
  STA BSTATE
  LDA #$00
  STA B_T
  JSR NEXT_RND
  LDA RND
  AND #$0F
  CLC
  ADC #RIM_BACK
  STA T0
  CPX #$00
  BNE .se_l
  LDA HOOPX                    ; canestro di destra: rimbalza verso il centro
  SEC
  SBC T0
  BRA .se_x
.se_l:
  LDA HOOPX+1
  CLC
  ADC T0
.se_x:
  STA T4
  LDA B_GXH
  STA T5
  LDA #$04
  STA T6
  JSR VEL_CALC
  LDA T0
  STA B_VXL
  LDA T1
  STA B_VXH
  JSR NEXT_RND
  LDA RND
  AND #$3F
  CLC
  ADC #80
  STA T4
  LDA B_GYH
  STA T5
  JSR VEL_CALC
  LDA T0
  STA B_VYL
  LDA T1
  STA B_VYH
  LDA #30
  STA B_H
  RTS


; ===============================================================
;  FINE PARTITA: il campo resta, appare il pannello del vincitore
; ===============================================================
GAME_OVER:
  LDX #$FF
  TXS
  LDA #45                      ; il chime dell'ultimo canestro finisce di suonare
  STA GO_DELAY
.go_w:
  JSR WAIT_FRAME
  DEC GO_DELAY
  BNE .go_w
  JSR HIDE_SPRITES
  JSR VDP_INT_OFF
  LDA #<END_REC
  STA PTR
  LDA #>END_REC
  STA PTR+1
  JSR DRAW_RECORDS
  LDA WINNER
  BNE .go_elia
  LDA #<BANNER_D
  STA PTR
  LDA #>BANNER_D
  BRA .go_banner
.go_elia:
  LDA #<BANNER_E
  STA PTR
  LDA #>BANNER_E
.go_banner:
  STA PTR+1
  JSR DRAW_RECORDS
  JSR DRAW_HUD                 ; punteggio finale
  JSR VDP_INT_ON
  LDA #$01                     ; applauso, gridi, poi la canzone celebrativa
  STA SND_BUSY
  LDA #CMD_WIN
  STA SND_CMD
  LDA #$00
  STA ARMED
  LDA #60                      ; dopo la canzone, mezzo secondo prima di accettare il pulsante
  STA GO_DELAY
.go_loop:
  JSR WAIT_FRAME
  JSR READ_JOY
  LDA P_JOY
  ORA P_JOY+1
  AND #BTN_MASK
  BNE .go_pressed
  LDA ARMED                    ; pulsanti rilasciati
  BNE .go_loop
  LDA SND_BUSY                 ; ... ma si arma solo a canzone finita
  BNE .go_loop
  LDA GO_DELAY
  BNE .go_dec
  JSR VDP_INT_OFF
  LDA #<END_PRESS
  STA PTR
  LDA #>END_PRESS
  STA PTR+1
  JSR DRAW_RECORDS             ; compare "PRESS A BUTTON"
  JSR VDP_INT_ON
  LDA #$01
  STA ARMED
  BRA .go_loop
.go_dec:
  DEC GO_DELAY
  BRA .go_loop
.go_pressed:
  LDA ARMED
  BEQ .go_loop
  JMP TITLE


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


; ---------------------------------------------------------------
; NMI (vblank): unico punto che scrive la Sprite Attribute Table.
; Il main loop scrive solo in SAT_BUFFER (RAM). Quando il main loop deve
; scrivere sul VDP (schermate, punteggio) spegne l'interrupt del VDP
; con VDP_INT_OFF, cosi' l'NMI non puo' spezzare una sequenza di scrittura.
; ---------------------------------------------------------------
NMI_TASK:
  INC FRAME_CNT           ; conta i frame per WAIT_FRAME
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
  CPX #25               ; 6 sprite x 4 byte + Y=$D0 della 7a voce
  BNE .copy_sat
  JSR SND_TICK            ; musica ed effetti sonori (A,X,Y salvati dentro)
  RTS                     ; NMI_HANDLER del BIOS rilegge VREG e fa RTI

FRAME_CNT:     .byte $00
LAST_FRAME:    .byte $00

WAIT_FRAME:               ; aspetta il prossimo NMI (1 frame = 1/60 s)
  LDA FRAME_CNT
  CMP LAST_FRAME
  BEQ WAIT_FRAME
  STA LAST_FRAME
  RTS

; spegne l'interrupt del VDP subito dopo un NMI (ne arriva un altro fra ~16 ms)
VDP_INT_OFF:
  LDA FRAME_CNT
.io_wait:
  CMP FRAME_CNT
  BEQ .io_wait
  LDA #$C6                ; R1: 16K + display ON + INT OFF
  STA VREG
  LDA #(VDP_REGISTER_BITS | 1)
  STA VREG
  RTS

VDP_INT_ON:
  LDA #$E6                ; R1: 16K + display ON + INT ON
  STA VREG
  LDA #(VDP_REGISTER_BITS | 1)
  STA VREG
  RTS

; SAT: priorita' decrescente: 0 palla, 1-2 giocatore piu' vicino, 3-4 giocatore piu' lontano, 5 ombra
; (al massimo 4 sprite sulla stessa riga: palla + 2 giocatori + ombra)
SAT_BUFFER:    .byte HIDE_Y,$00,0,$0A   ; 0: palla
               .byte HIDE_Y,$00,$00,$04            ; 1: giocatore vicino, busto
               .byte HIDE_Y,$00,$00,$0F            ; 2: giocatore vicino, gambe
               .byte HIDE_Y,$00,$00,$04            ; 3: giocatore lontano, busto
               .byte HIDE_Y,$00,$00,$0F            ; 4: giocatore lontano, gambe
               .byte HIDE_Y,$00,4,$01 ; 5: ombra della palla
               .byte $D0                           ; 6: Y=$D0 = fine lista

HIDE_SPRITES:
  LDA #HIDE_Y
  STA SAT_BUFFER
  STA SAT_BUFFER+4
  STA SAT_BUFFER+8
  STA SAT_BUFFER+12
  STA SAT_BUFFER+16
  STA SAT_BUFFER+20
  RTS


; ---------------------------------------------------------------
; riempie SAT_BUFFER (solo RAM) dallo stato di gioco
; ---------------------------------------------------------------
DRAW_ALL:
  ; --- palla: centro = (GX, GY - H - 3), sprite 16x16 col centro del pallone in (7,7)
  LDA B_GXH
  SEC
  SBC #7
  STA SAT_BUFFER+1
  LDA B_GYH
  SEC
  SBC B_H
  BCC .da_by0
  SEC
  SBC #11                      ; 3 (raggio) + 7 (centro) + 1 (SAT)
  BCS .da_byok
.da_by0:
  LDA #$00
.da_byok:
  STA SAT_BUFFER
  ; --- ombra a terra, centrata sul punto (GX, GY)
  LDA B_GXH
  SEC
  SBC #8
  STA SAT_BUFFER+21
  LDA B_GYH
  SEC
  SBC #9
  STA SAT_BUFFER+20
  ; --- giocatori: chi e' piu' in basso sullo schermo e' piu' vicino, va davanti
  LDA P_FY
  CMP P_FY+1
  BCS .da_p0
  LDX #$01
  LDY #$04
  JSR DRAW_PLAYER
  LDX #$00
  LDY #$0C
  JSR DRAW_PLAYER
  RTS
.da_p0:
  LDX #$00
  LDY #$04
  JSR DRAW_PLAYER
  LDX #$01
  LDY #$0C
  JSR DRAW_PLAYER
  RTS

; X = giocatore, Y = offset in SAT_BUFFER dello sprite del busto (gambe a +4)
DRAW_PLAYER:
  STY T6
  LDA P_JUMP,X
  TAY
  LDA JUMP_H,Y                 ; quanto e' sollevato da terra
  STA T0
  LDA P_FY,X
  SEC
  SBC T0
  STA T1                       ; piedi sollevati
  LDY T6
  SEC
  SBC #33                      ; busto: piedi - 32 - 1 (SAT)
  STA SAT_BUFFER,Y
  LDA T1
  SEC
  SBC #17                      ; gambe: piedi - 16 - 1
  STA SAT_BUFFER+4,Y
  LDA P_X,X
  STA SAT_BUFFER+1,Y
  STA SAT_BUFFER+5,Y
  ; --- posa del busto
  LDA P_JUMP,X
  BNE .dp_up
  LDA BSTATE
  BNE .dp_idle
  CPX HOLDER
  BEQ .dp_idle
  LDA #SPR_TOP_DEF             ; difesa: braccia larghe
  BRA .dp_top
.dp_idle:
  LDA #SPR_TOP_IDLE
  BRA .dp_top
.dp_up:
  LDA #SPR_TOP_SHOOT           ; braccia alzate
.dp_top:
  STA T2
  ; --- posa delle gambe
  LDA P_JUMP,X
  BNE .dp_legj
  LDA P_WALK,X
  AND #$08
  BEQ .dp_lega
  LDA #SPR_BOT_B
  BRA .dp_legs
.dp_lega:
  LDA #SPR_BOT_A
  BRA .dp_legs
.dp_legj:
  LDA #SPR_BOT_JUMP
.dp_legs:
  STA T3
  LDA P_FACE,X
  BEQ .dp_right
  LDA T2
  CLC
  ADC #SPR_LEFT_ADD
  STA T2
  LDA T3
  CLC
  ADC #SPR_LEFT_ADD
  STA T3
.dp_right:
  LDA T2
  STA SAT_BUFFER+2,Y
  LDA T3
  STA SAT_BUFFER+6,Y
  LDA TOP_COLOR,X
  STA SAT_BUFFER+3,Y
  LDA BOT_COLOR,X
  STA SAT_BUFFER+7,Y
  RTS

TOP_COLOR:     .byte $04,$08                ; maglia: Davide blu scuro, Elia rosso
BOT_COLOR:     .byte $0F,$01                ; calzoncini: Davide bianco, Elia nero
HOOPX:         .byte 233,22                 ; canestro attaccato da Davide (destra) / da Elia (sinistra)


; ---------------------------------------------------------------
; punteggi (cifre grandi) a fianco dei nomi, messaggi
; ---------------------------------------------------------------
UPDATE_HUD:
  JSR VDP_INT_OFF
  JSR DRAW_HUD
  JSR VDP_INT_ON
  RTS

DRAW_HUD:
  LDX #$00
  LDA #$08                      ; riga 0, colonna 8: a fianco di "DAVIDE"
  JSR DRAW_SCORE
  LDX #$01
  LDA #$14                      ; riga 0, colonna 20: a fianco di "ELIA"
  JSR DRAW_SCORE
  RTS

; X = giocatore, A = byte basso dell'indirizzo name table (riga 0)
DRAW_SCORE:
  STA T4
  LDA P_SCORE,X
  LDY #$00
.ds_t:
  CMP #10
  BCC .ds_o
  SBC #10
  INY
  BRA .ds_t
.ds_o:
  STA T5                        ; unita'
  STY T6                        ; decine
  LDA T6
  ASL A
  ASL A
  CLC
  ADC #BIG0
  STA T0
  LDA T4
  STA T1
  LDA #(VDP_WRITE_VRAM_BIT | >VDP_NAME_TABLE_BASE)
  STA T2
  JSR DRAW_BIG
  LDA T5
  ASL A
  ASL A
  CLC
  ADC #BIG0
  STA T0
  LDA T4
  CLC
  ADC #$02
  STA T1
  JSR DRAW_BIG
  RTS

; disegna un carattere grande 2x2 tile
; T0 = primo tile (alto-sx), T1/T2 = indirizzo VRAM di scrittura (lo/hi con bit $40)
DRAW_BIG:
  LDA T1
  STA VREG
  LDA T2
  STA VREG
  LDA T0
  STA VDATA
  CLC
  ADC #1
  STA VDATA
  LDA T1                        ; riga sotto = indirizzo + 32
  CLC
  ADC #32
  STA VREG
  LDA T2
  ADC #0
  STA VREG
  LDA T0
  CLC
  ADC #2
  STA VDATA
  CLC
  ADC #1
  STA VDATA
  RTS

; scrive il messaggio MSG_NEW (20 tile) sulla riga 2, colonne 6-25
DRAW_MSG:
  LDA MSG_NEW
  ASL A
  ASL A
  STA T1                        ; n*4
  ASL A
  ASL A                         ; n*16
  CLC
  ADC T1                        ; n*20
  CLC
  ADC #<MSG_TAB
  STA PTR
  LDA #>MSG_TAB
  ADC #0
  STA PTR+1
  JSR VDP_INT_OFF
  LDA #(2*32+6)
  STA VREG
  LDA #(VDP_WRITE_VRAM_BIT | >VDP_NAME_TABLE_BASE)
  STA VREG
  LDY #$00
.dm_c:
  LDA (PTR),Y
  STA VDATA
  INY
  CPY #20
  BNE .dm_c
  JSR VDP_INT_ON
  RTS


; ---------------------------------------------------------------
; disegna i record di una schermata sulla name table:
;   .byte riga, colonna, lunghezza, tile...   (terminatore: riga = $FF)
; PTR = inizio dei record. VDP libero (VDP_INT_OFF).
; ---------------------------------------------------------------
DRAW_RECORDS:
.dr_next:
  LDY #0
  LDA (PTR),Y
  CMP #$FF
  BEQ .dr_end
  STA T0                        ; riga
  INY
  LDA (PTR),Y
  STA T1                        ; colonna
  INY
  LDA (PTR),Y
  STA T2                        ; lunghezza
  LDA T0
  AND #$07
  ASL A
  ASL A
  ASL A
  ASL A
  ASL A
  CLC
  ADC T1
  STA VREG                      ; byte basso: (riga mod 8)*32 + colonna
  LDA T0
  LSR A
  LSR A
  LSR A
  CLC
  ADC #(VDP_WRITE_VRAM_BIT | >VDP_NAME_TABLE_BASE)
  STA VREG                      ; byte alto: $78 + riga/8
  INY
.dr_copy:
  LDA (PTR),Y
  STA VDATA
  INY
  DEC T2
  BNE .dr_copy
  TYA                           ; PTR += 3 + lunghezza
  CLC
  ADC PTR
  STA PTR
  BCC .dr_next
  INC PTR+1
  BRA .dr_next
.dr_end:
  RTS


; ---------------------------------------------------------------
; VDP
; ---------------------------------------------------------------
CLEAR_NAME_TABLE:
  LDA #<VDP_NAME_TABLE_BASE
  STA VREG
  LDA #(VDP_WRITE_VRAM_BIT | >VDP_NAME_TABLE_BASE)
  STA VREG
  LDX #3                        ; 768 byte = 3 pagine da 256
.cn_page:
  LDY #0
.cn_byte:
  LDA #$00
  STA VDATA
  DEY
  BNE .cn_byte
  DEX
  BNE .cn_page
  RTS

; copia il campo di gioco (VDP_NAME) nella name table
LOAD_GAME_NAME_TABLE:
  LDA #<VDP_NAME_TABLE_BASE
  STA VREG
  LDA #(VDP_WRITE_VRAM_BIT | >VDP_NAME_TABLE_BASE)
  STA VREG
  LDA #<VDP_NAME
  STA VDP_INIT
  LDA #>VDP_NAME
  STA VDP_INIT_HI
.ln_loop:
  LDA (VDP_INIT)
  STA VDATA
  INC VDP_INIT
  BNE .ln_skip
  INC VDP_INIT_HI
.ln_skip:
  LDA VDP_INIT
  CMP #<VDP_END_NAME
  BNE .ln_loop
  LDA VDP_INIT_HI
  CMP #>VDP_END_NAME
  BNE .ln_loop
  RTS

; copia nella VRAM tutti i blocchi di VDP_BLOCKS (src, lunghezza, indirizzo VRAM):
; pattern dei 3 terzi, sprite, colori dei 3 terzi
VDP_LOAD_ALL:
  LDA #<VDP_BLOCKS
  STA PTR
  LDA #>VDP_BLOCKS
  STA PTR+1
  LDX #BLOCK_COUNT
.vl_blk:
  LDY #0
  LDA (PTR),Y
  STA VDP_INIT
  INY
  LDA (PTR),Y
  STA VDP_INIT_HI
  INY
  LDA (PTR),Y
  STA T0                        ; lunghezza, byte basso
  INY
  LDA (PTR),Y
  STA T1                        ; lunghezza, byte alto
  INY
  LDA (PTR),Y
  STA VREG                      ; indirizzo VRAM
  INY
  LDA (PTR),Y
  STA VREG
  LDY #0
.vl_cp:
  LDA (VDP_INIT),Y
  STA VDATA
  INY
  BNE .vl_y
  INC VDP_INIT_HI
.vl_y:
  LDA T0
  BNE .vl_d0
  DEC T1
.vl_d0:
  DEC T0
  LDA T0
  ORA T1
  BNE .vl_cp
  LDA PTR                       ; prossimo blocco: PTR += 6
  CLC
  ADC #6
  STA PTR
  BCC .vl_nc
  INC PTR+1
.vl_nc:
  DEX
  BNE .vl_blk
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
   .byte $03,$76,$03,$0E       ;R0: G2 | R1: 16K, 16x16 sprite | R2: name $3800 | R3: color $2000
                               ;R4: pattern $0000 | R5: SAT $3B00 | R6: sprite pattern $1800 | R7: sfondo grigio


; ===============================================================
;  TABELLE (generate)
; ===============================================================
; blocchi da copiare nella VRAM: sorgente (2), lunghezza (2), indirizzo VRAM + bit di scrittura (2)
VDP_BLOCKS:
  .byte <PAT0,>PAT0,<(PAT0_END-PAT0),>(PAT0_END-PAT0),$00,$40
  .byte <PAT1,>PAT1,<(PAT1_END-PAT1),>(PAT1_END-PAT1),$00,$48
  .byte <PAT2,>PAT2,<(PAT2_END-PAT2),>(PAT2_END-PAT2),$00,$50
  .byte <VDP_SPRITE,>VDP_SPRITE,<(VDP_END_SPRITE-VDP_SPRITE),>(VDP_END_SPRITE-VDP_SPRITE),$00,$58
  .byte <COL0,>COL0,<(COL0_END-COL0),>(COL0_END-COL0),$00,$60
  .byte <COL1,>COL1,<(COL1_END-COL1),>(COL1_END-COL1),$00,$68
  .byte <COL2,>COL2,<(COL2_END-COL2),>(COL2_END-COL2),$00,$70


; ===============================================================
;  SONORO  -  due AY-3-8910 (sinistro = Davide, destro = Elia)
;  Tutto il suono e' suonato da SND_TICK, chiamata dall'NMI a 60 Hz.
;  Il main loop non scrive mai sugli AY: lascia solo comandi e flag
;  (SND_CMD, SFX_REQ, SFX_DRIB), cosi' non ci sono conflitti.
;  Gli AY si scrivono dagli shadow SH_L / SH_R (registri 0-10).
;
;  In partita: canale A = chime / ping, B = rumore (retina, applauso),
;  C = colpi bassi (palleggio, ferro, stoppata).
;  Canzoni: 0 = titolo, 1 = vittoria (4 tracce: melodia, arpeggio, basso, batteria).
; ===============================================================

; chiamata una volta da RESET (interrupt VDP ancora spento)
SND_INIT:
  LDA #$A5
  STA SND_RND
  LDA #$00
  STA SND_CMD
  STA SND_PH
  LDA #$FF                      ; mixer: tutto spento mentre si azzera
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
  STA SFX_REQ
  STA SFX_EVT
  STA SFX_STEP
  STA SFX_APPL
  STA SFX_ADLY
  STA SFX_DRIB
  STA SFX_DRIB+1
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
  BNE .st_t
  JSR SND_GAME_MODE
  BRA .st_run
.st_t:
  CMP #CMD_TITLE
  BNE .st_w
  LDA #$00                      ; canzone 0 = titolo
  JSR SND_START
  BRA .st_run
.st_w:
  JSR CELEB_START               ; CMD_WIN: applauso, gridi, poi la canzone 1
.st_run:
  LDA SND_MODE
  BEQ .st_sfx
  CMP #$01
  BNE .st_cel
  JSR MUS_TICK
  BRA .st_flush
.st_cel:
  JSR CELEB_TICK
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
; avvia una canzone: A = 0 titolo, 1 vittoria
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
; rumore da applauso su un chip: A = volume base, Y = chip * 16.
; Il volume e' abbassato di 0-7 a caso ogni frame (crepitio dei battimani)
; e il periodo del rumore cambia a caso (5-12). Preserva Y.
; ---------------------------------------------------------------
APPL_NOISE:
  STA SN1
  LDA SND_RND
  ASL A
  BCC .an_r
  EOR #$1D
.an_r:
  STA SND_RND
  AND #$07
  STA SN0
  LDA SN1
  SEC
  SBC SN0
  BCS .an_v
  LDA #$00
.an_v:
  STA SH_L+9,Y
  LDA SND_RND
  LSR A
  LSR A
  LSR A
  AND #$07
  CLC
  ADC #$05
  STA SH_L+6,Y
  RTS

; ---------------------------------------------------------------
; effetti sonori di gioco (un frame). Chip 0 = Davide, chip 1 = Elia.
;   canale A = chime / ping, B = rumore (retina, applauso), C = colpi bassi
; Priorita' in ogni canale: effetto a tabella > applauso / palleggio.
; ---------------------------------------------------------------
SFX_TICK:
  LDA SND_RND                   ; LFSR per il crepitio
  ASL A
  BCC .sf_r
  EOR #$1D
.sf_r:
  STA SND_RND
  LDA SFX_REQ                   ; nuova richiesta di effetto?
  BEQ .sf_noreq
  STA SFX_EVT
  TAX
  LDA #$00
  STA SFX_STEP
  STA SFX_REQ
  LDA EVT_ADLY,X
  BEQ .sf_noreq
  STA SFX_ADLY                  ; l'applauso parte dopo un po'
.sf_noreq:
  LDA SFX_ADLY
  BEQ .sf_chips
  DEC SFX_ADLY
  BNE .sf_chips
  LDA #$01
  STA SFX_APPL                  ; parte l'applauso
.sf_chips:
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
  ; ---- palleggio: tonfo sul canale C del chip del giocatore che palleggia
  LDA SFX_DRIB,X
  BEQ .sf_nodr
  TAX
  DEX                           ; passo 0..5
  LDA DRIB_V,X
  STA SH_L+10,Y
  LDA DRIB_TL,X
  STA SH_L+4,Y
  LDA DRIB_TH,X
  STA SH_L+5,Y
.sf_nodr:
  ; ---- applauso: rumore sul canale B di entrambi i chip
  LDA SFX_APPL
  BEQ .sf_noap
  LSR A
  LSR A
  LSR A                         ; un valore dell'inviluppo ogni 8 frame
  TAX
  LDA APPL_ENV,X
  JSR APPL_NOISE
.sf_noap:
  ; ---- effetto a tabella: sopra a tutto il resto
  LDA SFX_EVT
  BEQ .sf_next
  TAX
  LDA EVT_OFF,X
  CLC
  ADC SFX_STEP
  TAX                           ; X = posizione nelle tabelle EV*
  LDA EVA_V,X
  STA SH_L+8,Y
  LDA EVA_TL,X
  CPY #$00
  BEQ .sf_ea
  CLC
  ADC #$01                      ; il chip destro e' scordato di 1 passo (chorus)
.sf_ea:
  STA SH_L,Y
  LDA EVA_TH,X
  STA SH_L+1,Y
  LDA EVN_V,X
  BEQ .sf_en
  STA SH_L+9,Y
  LDA EVN_P,X
  STA SH_L+6,Y
.sf_en:
  LDA EVC_V,X
  BEQ .sf_next
  STA SH_L+10,Y
  LDA EVC_TL,X
  STA SH_L+4,Y
  LDA EVC_TH,X
  STA SH_L+5,Y
.sf_next:
  LDX SND_T1
  DEX
  BMI .sf_adv
  JMP .sf_chip
.sf_adv:
  LDA SFX_EVT                   ; avanza l'effetto
  BEQ .sf_a1
  INC SFX_STEP
  LDX SFX_EVT
  LDA SFX_STEP
  CMP EVT_LEN,X
  BCC .sf_a1
  LDA #$00
  STA SFX_EVT
.sf_a1:
  LDA SFX_APPL                  ; avanza l'applauso
  BEQ .sf_a2
  INC SFX_APPL
  LDA SFX_APPL
  CMP #(APPL_LEN+1)
  BCC .sf_a2
  LDA #$00
  STA SFX_APPL
.sf_a2:
  LDX #$01                      ; avanza i due palleggi
.sf_a3:
  LDA SFX_DRIB,X
  BEQ .sf_a4
  INC SFX_DRIB,X
  LDA SFX_DRIB,X
  CMP #(DRIB_LEN+1)
  BCC .sf_a4
  LDA #$00
  STA SFX_DRIB,X
.sf_a4:
  DEX
  BPL .sf_a3
  RTS


; ---------------------------------------------------------------
; finale: prima l'applauso, poi i gridi, poi la canzone di vittoria
; ---------------------------------------------------------------
CELEB_START:
  JSR SND_GAME_MODE             ; silenzio, mixer = tono A + rumore B + tono C
  LDA #$02
  STA SND_MODE
  LDA #$01
  STA SND_BUSY
  LDA #$00
  STA SND_STAGE
  STA SND_T2
  RTS

CELEB_TICK:
  INC SND_T2
  LDA #$00                      ; toni a zero: restano solo quelli della fase
  STA SH_L+8
  STA SH_L+10
  STA SH_R+8
  STA SH_R+10
  LDA SND_STAGE
  BNE .cb_cheer
  LDA SND_T2                    ; ---- fase 0: grande applauso
  CMP #CELEB_APPL_LEN
  BCC .cb_ap
  LDA #$01
  STA SND_STAGE
  LDA #$00
  STA SND_T2
  RTS
.cb_ap:
  LSR A
  LSR A
  LSR A
  LSR A                         ; un valore dell'inviluppo ogni 16 frame
  TAX
  LDA CAPPL_ENV,X
  JMP CELEB_NOISE
.cb_cheer:
  LDA SND_T2                    ; ---- fase 1: gridi "whoo!" + brusio della folla
  CMP #CHEER_LEN
  BCC .cb_ch
  LDA #$01                      ; finito: parte la canzone di vittoria
  JMP SND_START
.cb_ch:
  LSR A
  TAX                           ; passo 0..55 (uno ogni 2 frame)
  LDA CHEER_V,X
  STA SH_L+8
  STA SH_R+8
  SEC
  SBC #$03
  BCS .cb_cv
  LDA #$00
.cb_cv:
  STA SH_L+10
  STA SH_R+10
  LDA CHEER_TL,X
  STA SH_L
  CLC
  ADC #$03                      ; chip destro scordato: effetto folla
  STA SH_R
  LDA CHEER_TH,X
  STA SH_L+1
  STA SH_R+1
  LDA CHEER_CTL,X
  STA SH_L+4
  CLC
  ADC #$02
  STA SH_R+4
  LDA CHEER_CTH,X
  STA SH_L+5
  STA SH_R+5
  LDA #$06
CELEB_NOISE:                    ; A = volume base del rumore, su entrambi i chip
  STA SND_T1
  LDY #$00
  JSR APPL_NOISE
  LDA SND_T1
  LDY #$10
  JSR APPL_NOISE
  RTS


; arco da 3 punti: semiasse X dell'ellisse per |dy| = 0..62 (dentro = 2 punti)
ARCDX_TAB:
  .byte $54,$53,$53,$53,$53,$53,$53,$53,$53,$53,$52,$52,$52,$52,$51,$51
  .byte $51,$50,$50,$4F,$4F,$4F,$4E,$4E,$4D,$4C,$4C,$4B,$4A,$4A,$49,$48
  .byte $47,$47,$46,$45,$44,$43,$42,$41,$40,$3F,$3D,$3C,$3B,$39,$38,$36
  .byte $35,$33,$31,$2F,$2D,$2B,$29,$26,$24,$21,$1D,$19,$15,$0F,$00

; limite sinistro del campo (X sprite) per Y piedi = 64..188; il limite destro e' 240 - valore
XMIN_TAB:
  .byte $15,$15,$14,$14,$14,$14,$14,$14,$14,$13,$13,$13,$13,$13,$13,$12
  .byte $12,$12,$12,$12,$12,$11,$11,$11,$11,$11,$11,$11,$10,$10,$10,$10
  .byte $10,$10,$0F,$0F,$0F,$0F,$0F,$0F,$0F,$0E,$0E,$0E,$0E,$0E,$0E,$0D
  .byte $0D,$0D,$0D,$0D,$0D,$0D,$0C,$0C,$0C,$0C,$0C,$0C,$0B,$0B,$0B,$0B
  .byte $0B,$0B,$0A,$0A,$0A,$0A,$0A,$0A,$0A,$09,$09,$09,$09,$09,$09,$08
  .byte $08,$08,$08,$08,$08,$08,$07,$07,$07,$07,$07,$07,$06,$06,$06,$06
  .byte $06,$06,$06,$05,$05,$05,$05,$05,$05,$04,$04,$04,$04,$04,$04,$04
  .byte $04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04,$04

; altezza del salto (pixel) in funzione dei frame rimasti P_JUMP = 0..24
JUMP_H:
  .byte $00,$01,$03,$05,$07,$09,$0A,$0B,$0C,$0D,$0D,$0E,$0E
  .byte $0E,$0E,$0D,$0D,$0C,$0B,$0A,$09,$07,$05,$03,$01

; altezza della palla durante il palleggio (16 frame)
DRIB_TAB:
  .byte $12,$12,$11,$0F,$0E,$0B,$08,$04,$00,$04,$08,$0B,$0E,$0F,$11,$12

; altezza della palla nel tiro: 33 passi, da 36 (mani) a 30 (ferro) con arco di 20 pixel
HT_TAB:
  .byte $24,$26,$28,$2A,$2C,$2E,$2F,$30,$32,$32,$33
  .byte $34,$34,$35,$35,$35,$35,$35,$34,$34,$33,$32
  .byte $31,$30,$2E,$2D,$2B,$29,$28,$25,$23,$21,$1E

; rimbalzo della palla libera: cade dal ferro e fa un secondo rimbalzo (17 passi)
BNC_TAB:
  .byte $1E,$1E,$1C,$1A,$16,$12,$0D,$07,$00,$03,$05,$07,$07,$07,$05,$03,$00

; palla che attraversa la retina (13 passi)
NET_TAB:
  .byte $1E,$1C,$19,$16,$14,$12,$0F,$0C,$0A,$08,$05,$02,$00

; sprite 16x16 (generatore sprite): palla, ombra, 3 pose del busto e 3 delle gambe, destra e sinistra
VDP_SPRITE:
  ; BALL  (sprite name 0)
  .byte $00,$00,$00,$00,$03,$07,$0F,$0F
  .byte $0F,$07,$03,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$80,$C0,$E0,$E0
  .byte $E0,$C0,$80,$00,$00,$00,$00,$00
  ; SHADOW  (sprite name 4)
  .byte $00,$00,$00,$00,$00,$00,$00,$07
  .byte $0F,$07,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$E0
  .byte $F0,$E0,$00,$00,$00,$00,$00,$00
  ; TOP_IDLE_R  (sprite name 8)
  .byte $00,$00,$00,$01,$01,$01,$00,$00
  .byte $03,$03,$07,$07,$0F,$0F,$1B,$03
  .byte $00,$00,$E0,$F0,$F0,$F0,$E0,$00
  .byte $F8,$FC,$FC,$FE,$FB,$FB,$F8,$F8
  ; TOP_SHOOT_R  (sprite name 12)
  .byte $00,$0C,$0C,$0C,$0D,$0F,$07,$07
  .byte $07,$06,$07,$07,$07,$07,$07,$07
  .byte $0C,$0C,$0C,$0C,$CC,$EC,$F8,$F8
  .byte $D8,$18,$F8,$F0,$F0,$F0,$F0,$F0
  ; TOP_DEF_R  (sprite name 16)
  .byte $00,$00,$01,$03,$03,$03,$01,$00
  .byte $07,$07,$1F,$77,$C7,$07,$07,$07
  .byte $00,$00,$C0,$E0,$E0,$E0,$C0,$00
  .byte $F0,$F8,$FC,$F6,$F3,$F0,$F0,$F0
  ; TOP_IDLE_L  (sprite name 20)
  .byte $00,$00,$07,$0F,$0F,$0F,$07,$00
  .byte $1F,$3F,$3F,$7F,$DF,$DF,$1F,$1F
  .byte $00,$00,$00,$80,$80,$80,$00,$00
  .byte $C0,$C0,$E0,$E0,$F0,$F0,$D8,$C0
  ; TOP_SHOOT_L  (sprite name 24)
  .byte $30,$30,$30,$30,$33,$37,$1F,$1F
  .byte $1B,$18,$1F,$0F,$0F,$0F,$0F,$0F
  .byte $00,$30,$30,$30,$B0,$F0,$E0,$E0
  .byte $E0,$60,$E0,$E0,$E0,$E0,$E0,$E0
  ; TOP_DEF_L  (sprite name 28)
  .byte $00,$00,$03,$07,$07,$07,$03,$00
  .byte $0F,$1F,$3F,$6F,$CF,$0F,$0F,$0F
  .byte $00,$00,$80,$C0,$C0,$C0,$80,$00
  .byte $E0,$E0,$F8,$EE,$E3,$E0,$E0,$E0
  ; BOT_A_R  (sprite name 32)
  .byte $07,$07,$07,$07,$07,$03,$03,$06
  .byte $06,$06,$0C,$0C,$0C,$0C,$18,$78
  .byte $F0,$F0,$F0,$F0,$F0,$30,$30,$18
  .byte $18,$18,$0C,$0C,$0C,$0C,$06,$0F
  ; BOT_B_R  (sprite name 36)
  .byte $07,$07,$07,$07,$07,$01,$01,$01
  .byte $01,$01,$03,$03,$03,$03,$03,$0F
  .byte $F0,$F0,$F0,$F0,$F0,$E0,$E0,$E0
  .byte $E0,$E0,$30,$30,$30,$30,$30,$78
  ; BOT_JUMP_R  (sprite name 40)
  .byte $07,$07,$07,$07,$07,$03,$06,$0C
  .byte $0C,$18,$0C,$0C,$0C,$06,$00,$00
  .byte $F0,$F0,$F0,$F0,$F0,$30,$18,$0C
  .byte $0C,$06,$0C,$0C,$0C,$18,$00,$00
  ; BOT_A_L  (sprite name 44)
  .byte $0F,$0F,$0F,$0F,$0F,$0C,$0C,$18
  .byte $18,$18,$30,$30,$30,$30,$60,$F0
  .byte $E0,$E0,$E0,$E0,$E0,$C0,$C0,$60
  .byte $60,$60,$30,$30,$30,$30,$18,$1E
  ; BOT_B_L  (sprite name 48)
  .byte $0F,$0F,$0F,$0F,$0F,$07,$07,$07
  .byte $07,$07,$0C,$0C,$0C,$0C,$0C,$1E
  .byte $E0,$E0,$E0,$E0,$E0,$80,$80,$80
  .byte $80,$80,$C0,$C0,$C0,$C0,$C0,$F0
  ; BOT_JUMP_L  (sprite name 52)
  .byte $0F,$0F,$0F,$0F,$0F,$0C,$18,$30
  .byte $30,$60,$30,$30,$30,$18,$00,$00
  .byte $E0,$E0,$E0,$E0,$E0,$C0,$60,$30
  .byte $30,$18,$30,$30,$30,$60,$00,$00
VDP_END_SPRITE:

; pattern terzo 0: tile 00-F3 (8 byte per tile)
PAT0:
  .byte $00,$00,$00,$00,$00,$00,$00,$00   ; tile 00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $A8,$54,$A8,$54,$A8,$54,$A8,$54
  .byte $2A,$15,$2A,$15,$2A,$15,$2A,$15
  .byte $00,$00,$00,$00,$01,$01,$01,$01
  .byte $FF,$FF,$C0,$C0,$80,$80,$80,$80
  .byte $FF,$FF,$00,$00,$00,$00,$00,$00
  .byte $FF,$FF,$01,$01,$01,$01,$01,$01
  .byte $FF,$FF,$80,$80,$80,$80,$80,$80
  .byte $FF,$FF,$03,$03,$01,$01,$01,$01
  .byte $00,$00,$00,$00,$80,$80,$80,$80
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00   ; tile 10
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
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00   ; tile 20
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
  .byte $70,$88,$98,$A8,$C8,$88,$70,$00   ; tile 30
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
  .byte $70,$88,$A8,$B8,$B0,$80,$78,$00   ; tile 40
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
  .byte $F0,$88,$88,$F0,$80,$80,$80,$00   ; tile 50
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
  .byte $00,$00,$00,$00,$00,$00,$00,$00   ; tile 60
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
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00   ; tile 70
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
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $07,$07,$18,$18,$18,$18,$19,$19   ; tile 80
  .byte $E0,$E0,$18,$18,$78,$78,$98,$98
  .byte $1E,$1E,$18,$18,$07,$07,$00,$00
  .byte $18,$18,$18,$18,$E0,$E0,$00,$00
  .byte $01,$01,$07,$07,$01,$01,$01,$01
  .byte $80,$80,$80,$80,$80,$80,$80,$80
  .byte $01,$01,$01,$01,$07,$07,$00,$00
  .byte $80,$80,$80,$80,$E0,$E0,$00,$00
  .byte $07,$07,$18,$18,$00,$00,$01,$01
  .byte $E0,$E0,$18,$18,$18,$18,$E0,$E0
  .byte $06,$06,$18,$18,$1F,$1F,$00,$00
  .byte $00,$00,$00,$00,$F8,$F8,$00,$00
  .byte $1F,$1F,$00,$00,$00,$00,$01,$01
  .byte $F8,$F8,$18,$18,$60,$60,$E0,$E0
  .byte $00,$00,$18,$18,$07,$07,$00,$00
  .byte $18,$18,$18,$18,$E0,$E0,$00,$00
  .byte $00,$00,$01,$01,$06,$06,$18,$18   ; tile 90
  .byte $60,$60,$E0,$E0,$60,$60,$60,$60
  .byte $1F,$1F,$00,$00,$00,$00,$00,$00
  .byte $F8,$F8,$60,$60,$60,$60,$00,$00
  .byte $1F,$1F,$18,$18,$1F,$1F,$00,$00
  .byte $F8,$F8,$00,$00,$E0,$E0,$18,$18
  .byte $00,$00,$18,$18,$07,$07,$00,$00
  .byte $18,$18,$18,$18,$E0,$E0,$00,$00
  .byte $01,$01,$06,$06,$18,$18,$1F,$1F
  .byte $F8,$F8,$00,$00,$00,$00,$E0,$E0
  .byte $18,$18,$18,$18,$07,$07,$00,$00
  .byte $18,$18,$18,$18,$E0,$E0,$00,$00
  .byte $1F,$1F,$00,$00,$00,$00,$01,$01
  .byte $F8,$F8,$18,$18,$60,$60,$80,$80
  .byte $06,$06,$06,$06,$06,$06,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $07,$07,$18,$18,$18,$18,$07,$07   ; tile A0
  .byte $E0,$E0,$18,$18,$18,$18,$E0,$E0
  .byte $18,$18,$18,$18,$07,$07,$00,$00
  .byte $18,$18,$18,$18,$E0,$E0,$00,$00
  .byte $07,$07,$18,$18,$18,$18,$07,$07
  .byte $E0,$E0,$18,$18,$18,$18,$F8,$F8
  .byte $00,$00,$00,$00,$1F,$1F,$00,$00
  .byte $18,$18,$60,$60,$80,$80,$00,$00
  .byte $1F,$1F,$01,$01,$01,$01,$01,$01
  .byte $F8,$F8,$80,$80,$80,$80,$80,$80
  .byte $01,$01,$01,$01,$01,$01,$00,$00
  .byte $80,$80,$80,$80,$80,$80,$00,$00
  .byte $01,$01,$06,$06,$18,$18,$18,$18
  .byte $80,$80,$60,$60,$18,$18,$18,$18
  .byte $1F,$1F,$18,$18,$18,$18,$00,$00
  .byte $F8,$F8,$18,$18,$18,$18,$00,$00
  .byte $18,$18,$18,$18,$1E,$1E,$19,$19   ; tile B0
  .byte $18,$18,$18,$18,$18,$18,$98,$98
  .byte $18,$18,$18,$18,$18,$18,$00,$00
  .byte $78,$78,$18,$18,$18,$18,$00,$00
  .byte $18,$18,$18,$18,$18,$18,$1F,$1F
  .byte $18,$18,$18,$18,$18,$18,$F8,$F8
  .byte $18,$18,$18,$18,$18,$18,$00,$00
  .byte $18,$18,$18,$18,$18,$18,$00,$00
  .byte $1F,$1F,$18,$18,$18,$18,$1F,$1F
  .byte $F8,$F8,$00,$00,$00,$00,$E0,$E0
  .byte $18,$18,$18,$18,$1F,$1F,$00,$00
  .byte $00,$00,$00,$00,$F8,$F8,$00,$00
  .byte $1F,$1F,$18,$18,$18,$18,$1F,$1F
  .byte $F8,$F8,$00,$00,$00,$00,$E0,$E0
  .byte $18,$18,$18,$18,$18,$18,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $07,$07,$01,$01,$01,$01,$01,$01   ; tile C0
  .byte $E0,$E0,$80,$80,$80,$80,$80,$80
  .byte $01,$01,$01,$01,$07,$07,$00,$00
  .byte $80,$80,$80,$80,$E0,$E0,$00,$00
  .byte $18,$18,$18,$18,$18,$18,$18,$18
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $18,$18,$18,$18,$1F,$1F,$00,$00
  .byte $00,$00,$00,$00,$F8,$F8,$00,$00
  .byte $07,$07,$18,$18,$18,$18,$18,$18
  .byte $E0,$E0,$18,$18,$00,$00,$00,$00
  .byte $18,$18,$18,$18,$07,$07,$00,$00
  .byte $00,$00,$18,$18,$E0,$E0,$00,$00
  .byte $07,$07,$18,$18,$18,$18,$18,$18
  .byte $E0,$E0,$18,$18,$18,$18,$18,$18
  .byte $18,$18,$18,$18,$07,$07,$00,$00
  .byte $18,$18,$18,$18,$E0,$E0,$00,$00
  .byte $1F,$1F,$18,$18,$18,$18,$18,$18   ; tile D0
  .byte $E0,$E0,$18,$18,$18,$18,$18,$18
  .byte $18,$18,$18,$18,$1F,$1F,$00,$00
  .byte $18,$18,$18,$18,$E0,$E0,$00,$00
  .byte $18,$18,$18,$18,$18,$18,$18,$18
  .byte $18,$18,$18,$18,$18,$18,$18,$18
  .byte $18,$18,$18,$18,$07,$07,$00,$00
  .byte $18,$18,$18,$18,$E0,$E0,$00,$00
  .byte $18,$18,$18,$18,$18,$18,$19,$19
  .byte $18,$18,$18,$18,$18,$18,$98,$98
  .byte $19,$19,$1E,$1E,$18,$18,$00,$00
  .byte $98,$98,$78,$78,$18,$18,$00,$00
  .byte $1F,$1F,$18,$18,$18,$18,$1F,$1F
  .byte $E0,$E0,$18,$18,$18,$18,$E0,$E0
  .byte $18,$18,$18,$18,$18,$18,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $18,$18,$18,$18,$06,$06,$01,$01   ; tile E0
  .byte $18,$18,$18,$18,$60,$60,$80,$80
  .byte $01,$01,$01,$01,$01,$01,$00,$00
  .byte $80,$80,$80,$80,$80,$80,$00,$00
  .byte $1F,$1F,$18,$18,$18,$18,$1F,$1F
  .byte $E0,$E0,$18,$18,$18,$18,$E0,$E0
  .byte $19,$19,$18,$18,$18,$18,$00,$00
  .byte $80,$80,$60,$60,$18,$18,$00,$00
  .byte $07,$07,$18,$18,$18,$18,$07,$07
  .byte $E0,$E0,$18,$18,$00,$00,$E0,$E0
  .byte $00,$00,$18,$18,$07,$07,$00,$00
  .byte $18,$18,$18,$18,$E0,$E0,$00,$00
  .byte $01,$01,$01,$01,$01,$01,$00,$00
  .byte $80,$80,$80,$80,$80,$80,$00,$00
  .byte $01,$01,$01,$01,$00,$00,$00,$00
  .byte $80,$80,$80,$80,$00,$00,$00,$00
  .byte $C0,$C0,$C0,$C0,$C0,$C0,$C0,$C0   ; tile F0
  .byte $C0,$C0,$C0,$C0,$C0,$C0,$C0,$C0
  .byte $33,$33,$33,$33,$0C,$0C,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
PAT0_END:

; colori terzo 0: tile 00-F3 (8 byte per tile)
COL0:
  .byte $11,$11,$11,$11,$11,$11,$11,$11   ; tile 00
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1   ; tile 10
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1   ; tile 20
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1   ; tile 30
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1   ; tile 40
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1   ; tile 50
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1   ; tile 60
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1   ; tile 70
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1   ; tile 80
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1   ; tile 90
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1   ; tile A0
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1   ; tile B0
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1   ; tile C0
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1   ; tile D0
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1   ; tile E0
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1   ; tile F0
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
COL0_END:

; pattern terzo 1: tile 00-90 (8 byte per tile)
PAT1:
  .byte $00,$00,$00,$00,$00,$00,$00,$00   ; tile 00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $A8,$54,$A8,$54,$A8,$54,$A8,$54
  .byte $00,$00,$00,$00,$7F,$80,$80,$7F
  .byte $00,$00,$00,$00,$E0,$10,$10,$E0
  .byte $00,$00,$00,$00,$C0,$F8,$FF,$1F
  .byte $00,$00,$00,$00,$00,$00,$80,$E0
  .byte $01,$01,$01,$01,$01,$01,$01,$01
  .byte $80,$80,$80,$80,$80,$80,$80,$80
  .byte $00,$00,$00,$00,$00,$00,$01,$07
  .byte $00,$00,$00,$00,$03,$1F,$FF,$F8
  .byte $00,$00,$00,$00,$07,$08,$08,$07
  .byte $00,$00,$00,$00,$FE,$01,$01,$FE
  .byte $2A,$15,$2A,$15,$2A,$15,$2A,$15
  .byte $55,$2A,$2A,$15,$0F,$00,$00,$00
  .byte $50,$A0,$A0,$40,$C0,$00,$00,$00
  .byte $01,$00,$00,$00,$00,$00,$00,$00   ; tile 10
  .byte $FC,$7F,$0F,$01,$00,$00,$00,$00
  .byte $00,$00,$E0,$F8,$7E,$1F,$07,$01
  .byte $00,$00,$00,$00,$00,$80,$C0,$F0
  .byte $00,$00,$00,$00,$00,$01,$03,$0F
  .byte $00,$00,$07,$1F,$7E,$F8,$E0,$80
  .byte $3F,$FE,$F0,$80,$00,$00,$00,$00
  .byte $80,$00,$00,$00,$00,$00,$00,$00
  .byte $05,$02,$02,$01,$00,$00,$00,$00
  .byte $55,$AA,$AA,$54,$FC,$00,$00,$00
  .byte $A8,$54,$A8,$54,$A8,$54,$00,$00
  .byte $0C,$0C,$0C,$0C,$0C,$18,$18,$18
  .byte $F8,$3E,$0F,$07,$01,$00,$00,$00
  .byte $00,$00,$00,$C0,$E0,$F0,$7C,$3E
  .byte $00,$00,$00,$03,$07,$0F,$3E,$7C
  .byte $1F,$7C,$F0,$E0,$80,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00   ; tile 20
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
  .byte $70,$88,$98,$A8,$C8,$88,$70,$00   ; tile 30
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
  .byte $70,$88,$A8,$B8,$B0,$80,$78,$00   ; tile 40
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
  .byte $F0,$88,$88,$F0,$80,$80,$80,$00   ; tile 50
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
  .byte $30,$30,$30,$30,$30,$18,$18,$18   ; tile 60
  .byte $2A,$15,$2A,$15,$2A,$15,$00,$00
  .byte $18,$18,$18,$18,$30,$30,$30,$30
  .byte $0F,$07,$03,$01,$00,$00,$00,$00
  .byte $00,$80,$C0,$E0,$F0,$78,$3C,$1C
  .byte $00,$01,$03,$07,$0F,$1E,$3C,$38
  .byte $F0,$E0,$C0,$80,$00,$00,$00,$00
  .byte $18,$18,$18,$18,$0C,$0C,$0C,$0C
  .byte $30,$30,$60,$60,$60,$60,$60,$60
  .byte $0E,$0F,$07,$03,$01,$01,$00,$00
  .byte $00,$00,$80,$80,$C0,$E0,$E0,$70
  .byte $00,$00,$01,$01,$03,$07,$07,$0E
  .byte $70,$F0,$E0,$C0,$80,$80,$00,$00
  .byte $0C,$0C,$06,$06,$06,$06,$06,$06
  .byte $00,$00,$00,$00,$00,$00,$00,$01
  .byte $60,$C0,$C0,$C0,$FF,$FF,$C0,$80
  .byte $00,$00,$00,$00,$FF,$FF,$00,$00   ; tile 70
  .byte $00,$00,$00,$00,$C0,$C0,$C0,$C0
  .byte $70,$38,$38,$1C,$1C,$0E,$0E,$06
  .byte $00,$00,$00,$01,$07,$1F,$7C,$F0
  .byte $00,$00,$1F,$FF,$F0,$00,$00,$00
  .byte $01,$FF,$FF,$81,$01,$01,$01,$01
  .byte $80,$FF,$FF,$80,$80,$80,$80,$80
  .byte $00,$C0,$FE,$FF,$07,$00,$00,$00
  .byte $00,$00,$00,$E0,$F8,$7E,$1F,$07
  .byte $00,$00,$00,$00,$00,$00,$80,$C0
  .byte $0E,$1C,$1C,$38,$38,$70,$70,$60
  .byte $00,$00,$00,$00,$03,$03,$03,$03
  .byte $06,$03,$03,$03,$FF,$FF,$03,$01
  .byte $00,$00,$00,$00,$00,$00,$00,$80
  .byte $01,$01,$01,$01,$01,$01,$03,$03
  .byte $80,$80,$80,$80,$80,$80,$00,$00
  .byte $C0,$C0,$C0,$C0,$C0,$C0,$C0,$C0   ; tile 80
  .byte $07,$07,$03,$03,$03,$01,$01,$01
  .byte $00,$00,$00,$80,$80,$80,$80,$80
  .byte $03,$07,$06,$0E,$1C,$18,$18,$18
  .byte $C0,$00,$00,$00,$00,$00,$00,$00
  .byte $F0,$78,$38,$1C,$1E,$0E,$06,$06
  .byte $00,$00,$00,$01,$01,$01,$01,$01
  .byte $E0,$E0,$C0,$C0,$C0,$80,$80,$80
  .byte $03,$03,$03,$03,$03,$03,$03,$03
  .byte $01,$01,$01,$01,$01,$01,$00,$00
  .byte $80,$80,$80,$80,$80,$80,$C0,$C0
  .byte $03,$03,$03,$03,$06,$06,$06,$06
  .byte $01,$01,$00,$00,$00,$00,$00,$00
  .byte $18,$18,$1C,$1E,$0E,$07,$07,$03
  .byte $06,$06,$0E,$1C,$18,$38,$70,$E0
  .byte $80,$80,$00,$00,$00,$00,$00,$00
  .byte $C0,$C0,$C0,$C0,$60,$60,$60,$60   ; tile 90
PAT1_END:

; colori terzo 1: tile 00-90 (8 byte per tile)
COL1:
  .byte $11,$11,$11,$11,$11,$11,$11,$11   ; tile 00
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE
  .byte $FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE
  .byte $FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE
  .byte $FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E   ; tile 10
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE
  .byte $FE,$FE,$FE,$FE,$FE,$FE,$FE,$FE
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1   ; tile 20
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1   ; tile 30
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1   ; tile 40
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1   ; tile 50
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E   ; tile 60
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E   ; tile 70
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E   ; tile 80
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E   ; tile 90
COL1_END:

; pattern terzo 2: tile 00-8A (8 byte per tile)
PAT2:
  .byte $00,$00,$00,$00,$00,$00,$00,$00   ; tile 00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $06,$06,$0C,$0C,$0C,$0C,$0C,$0C
  .byte $C0,$C0,$C0,$C0,$C0,$C0,$C0,$C0
  .byte $00,$00,$00,$00,$00,$00,$01,$01
  .byte $C0,$C0,$C0,$C0,$C0,$C0,$C0,$80
  .byte $F8,$7E,$1F,$07,$01,$00,$00,$00
  .byte $00,$00,$80,$F8,$FF,$1F,$00,$00
  .byte $01,$01,$01,$01,$C1,$FF,$FF,$01
  .byte $80,$80,$80,$80,$80,$FF,$FF,$80
  .byte $00,$00,$00,$07,$FF,$FC,$80,$00
  .byte $07,$1F,$7C,$F0,$C0,$00,$00,$00
  .byte $80,$00,$00,$00,$00,$00,$00,$00
  .byte $03,$03,$03,$03,$03,$03,$03,$01
  .byte $00,$00,$00,$00,$00,$00,$80,$80
  .byte $03,$03,$03,$03,$03,$03,$03,$03
  .byte $60,$60,$30,$30,$30,$30,$30,$30   ; tile 10
  .byte $0C,$18,$18,$18,$18,$18,$18,$30
  .byte $01,$01,$01,$03,$03,$03,$07,$06
  .byte $80,$80,$80,$80,$00,$00,$00,$00
  .byte $01,$01,$01,$01,$01,$01,$01,$01
  .byte $80,$80,$80,$80,$80,$80,$80,$80
  .byte $01,$01,$01,$01,$00,$00,$00,$00
  .byte $80,$80,$80,$C0,$C0,$C0,$E0,$60
  .byte $30,$18,$18,$18,$18,$18,$18,$0C
  .byte $30,$30,$3F,$3F,$30,$30,$60,$60
  .byte $00,$00,$FF,$FF,$00,$00,$00,$00
  .byte $C0,$C0,$C0,$C0,$00,$00,$00,$00
  .byte $06,$0E,$0C,$1C,$18,$38,$30,$70
  .byte $60,$70,$30,$38,$18,$1C,$0C,$0E
  .byte $03,$03,$03,$03,$00,$00,$00,$00
  .byte $0C,$0C,$FC,$FC,$0C,$0C,$06,$06
  .byte $00,$00,$00,$00,$00,$00,$00,$00   ; tile 20
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
  .byte $70,$88,$98,$A8,$C8,$88,$70,$00   ; tile 30
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
  .byte $70,$88,$A8,$B8,$B0,$80,$78,$00   ; tile 40
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
  .byte $F0,$88,$88,$F0,$80,$80,$80,$00   ; tile 50
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
  .byte $60,$60,$60,$60,$C0,$C0,$C0,$C0   ; tile 60
  .byte $00,$00,$01,$01,$03,$07,$0E,$0C
  .byte $60,$E0,$C0,$80,$80,$00,$00,$00
  .byte $06,$07,$03,$01,$01,$00,$00,$00
  .byte $00,$00,$80,$80,$C0,$E0,$70,$30
  .byte $06,$06,$06,$06,$03,$03,$03,$03
  .byte $00,$00,$00,$01,$01,$01,$01,$01
  .byte $C0,$C0,$C0,$80,$80,$80,$80,$80
  .byte $00,$00,$00,$00,$01,$03,$07,$0E
  .byte $1C,$38,$70,$E0,$C0,$80,$00,$00
  .byte $38,$1C,$0E,$07,$03,$01,$00,$00
  .byte $00,$00,$00,$00,$80,$C0,$E0,$70
  .byte $03,$03,$03,$01,$01,$01,$01,$01
  .byte $00,$00,$00,$80,$80,$80,$80,$80
  .byte $01,$03,$03,$03,$03,$03,$03,$06
  .byte $00,$00,$00,$01,$07,$0E,$3C,$F0
  .byte $3C,$78,$E0,$C0,$80,$00,$00,$00   ; tile 70
  .byte $3C,$1E,$07,$03,$01,$00,$00,$00
  .byte $00,$00,$00,$80,$E0,$70,$3C,$0F
  .byte $01,$00,$00,$00,$00,$00,$00,$00
  .byte $80,$C0,$C0,$C0,$C0,$C0,$C0,$60
  .byte $06,$06,$06,$06,$06,$06,$0C,$0C
  .byte $00,$00,$00,$00,$00,$00,$00,$01
  .byte $00,$00,$00,$00,$01,$0F,$7E,$F8
  .byte $01,$07,$1F,$7C,$F0,$C0,$00,$00
  .byte $E0,$80,$00,$00,$00,$00,$00,$00
  .byte $07,$01,$00,$00,$00,$00,$00,$00
  .byte $80,$E0,$F8,$3E,$0F,$03,$00,$00
  .byte $00,$00,$00,$00,$80,$F0,$7E,$1F
  .byte $00,$00,$00,$00,$00,$00,$00,$80
  .byte $60,$60,$60,$60,$60,$60,$30,$30
  .byte $0C,$0C,$0C,$0C,$18,$1B,$1B,$18
  .byte $00,$00,$00,$00,$01,$FF,$FF,$00   ; tile 80
  .byte $00,$00,$00,$03,$FF,$FE,$00,$00
  .byte $00,$00,$0F,$FF,$F8,$00,$00,$00
  .byte $1F,$FF,$F0,$80,$00,$00,$00,$00
  .byte $C0,$00,$00,$00,$00,$00,$00,$00
  .byte $03,$00,$00,$00,$00,$00,$00,$00
  .byte $F8,$FF,$0F,$01,$00,$00,$00,$00
  .byte $00,$00,$F0,$FF,$1F,$00,$00,$00
  .byte $00,$00,$00,$C0,$FF,$7F,$00,$00
  .byte $00,$00,$00,$00,$80,$FF,$FF,$00
  .byte $30,$30,$30,$30,$18,$D8,$D8,$18
PAT2_END:

; colori terzo 2: tile 00-8A (8 byte per tile)
COL2:
  .byte $11,$11,$11,$11,$11,$11,$11,$11   ; tile 00
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E   ; tile 10
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1   ; tile 20
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1   ; tile 30
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1   ; tile 40
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1   ; tile 50
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E   ; tile 60
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E   ; tile 70
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E   ; tile 80
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$1E
COL2_END:

; name table 32x24: riga 0-1 punteggi (cifre grandi scritte da DRAW_HUD), riga 1 nomi, riga 2 messaggi, resto campo
VDP_NAME:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00   ; riga 0
  .byte $00,$44,$41,$56,$49,$44,$45,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$45,$4C,$49,$41,$00,$00,$00   ; riga 1
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00   ; riga 2
  .byte $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
  .byte $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01   ; riga 3
  .byte $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
  .byte $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01   ; riga 4
  .byte $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
  .byte $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01   ; riga 5
  .byte $01,$02,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
  .byte $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$03,$01   ; riga 6
  .byte $01,$02,$04,$05,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$07
  .byte $08,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$09,$0A,$03,$01   ; riga 7
  .byte $01,$02,$03,$04,$05,$06,$01,$01,$01,$01,$01,$01,$01,$01,$01,$07
  .byte $08,$01,$01,$01,$01,$01,$01,$01,$01,$01,$09,$0A,$0B,$0C,$0D,$01   ; riga 8
  .byte $01,$02,$0E,$0F,$10,$11,$12,$13,$01,$01,$01,$01,$01,$01,$01,$07
  .byte $08,$01,$01,$01,$01,$01,$01,$01,$14,$15,$16,$17,$18,$19,$0D,$01   ; riga 9
  .byte $01,$1A,$1B,$01,$01,$01,$01,$1C,$1D,$01,$01,$01,$01,$01,$01,$07
  .byte $08,$01,$01,$01,$01,$01,$01,$1E,$1F,$01,$01,$01,$01,$60,$61,$01   ; riga 10
  .byte $01,$01,$62,$01,$01,$01,$01,$01,$63,$64,$01,$01,$01,$01,$01,$07
  .byte $08,$01,$01,$01,$01,$01,$65,$66,$01,$01,$01,$01,$01,$67,$01,$01   ; riga 11
  .byte $01,$01,$68,$01,$01,$01,$01,$01,$01,$69,$6A,$01,$01,$01,$01,$07
  .byte $08,$01,$01,$01,$01,$6B,$6C,$01,$01,$01,$01,$01,$01,$6D,$01,$01   ; riga 12
  .byte $01,$6E,$6F,$70,$70,$70,$70,$71,$01,$01,$72,$01,$01,$73,$74,$75
  .byte $76,$77,$78,$79,$01,$7A,$01,$01,$7B,$70,$70,$70,$70,$7C,$7D,$01   ; riga 13
  .byte $01,$7E,$7F,$01,$01,$01,$01,$80,$01,$01,$81,$82,$83,$84,$01,$07
  .byte $08,$01,$10,$85,$86,$87,$01,$01,$88,$01,$01,$01,$01,$89,$8A,$01   ; riga 14
  .byte $01,$8B,$01,$01,$01,$01,$01,$80,$01,$01,$8C,$80,$8D,$06,$01,$07
  .byte $08,$01,$6E,$8E,$88,$8F,$01,$01,$88,$01,$01,$01,$01,$01,$90,$01   ; riga 15
  .byte $01,$02,$01,$01,$01,$01,$01,$03,$01,$01,$04,$05,$01,$06,$07,$08
  .byte $09,$0A,$0B,$0C,$0D,$0E,$01,$01,$0F,$01,$01,$01,$01,$01,$10,$01   ; riga 16
  .byte $01,$11,$01,$01,$01,$01,$01,$03,$01,$01,$12,$13,$01,$01,$01,$14
  .byte $15,$01,$01,$01,$16,$17,$01,$01,$0F,$01,$01,$01,$01,$01,$18,$01   ; riga 17
  .byte $01,$19,$1A,$1A,$1A,$1A,$1A,$1B,$01,$01,$1C,$01,$01,$01,$01,$14
  .byte $15,$01,$01,$01,$01,$1D,$01,$01,$1E,$1A,$1A,$1A,$1A,$1A,$1F,$01   ; riga 18
  .byte $01,$60,$01,$01,$01,$01,$01,$01,$01,$61,$62,$01,$01,$01,$01,$14
  .byte $15,$01,$01,$01,$01,$63,$64,$01,$01,$01,$01,$01,$01,$01,$65,$01   ; riga 19
  .byte $66,$67,$01,$01,$01,$01,$01,$01,$68,$69,$01,$01,$01,$01,$01,$14
  .byte $15,$01,$01,$01,$01,$01,$6A,$6B,$01,$01,$01,$01,$01,$01,$6C,$6D   ; riga 20
  .byte $6E,$0C,$01,$01,$01,$01,$01,$6F,$70,$01,$01,$01,$01,$01,$01,$14
  .byte $15,$01,$01,$01,$01,$01,$01,$71,$72,$01,$01,$01,$01,$01,$73,$74   ; riga 21
  .byte $75,$01,$01,$01,$76,$77,$78,$79,$01,$01,$01,$01,$01,$01,$01,$14
  .byte $15,$01,$01,$01,$01,$01,$01,$01,$7A,$7B,$7C,$7D,$01,$01,$01,$7E   ; riga 22
  .byte $7F,$80,$81,$82,$83,$84,$01,$01,$01,$01,$01,$01,$01,$01,$01,$14
  .byte $15,$01,$01,$01,$01,$01,$01,$01,$01,$01,$85,$86,$87,$88,$89,$8A   ; riga 23
VDP_END_NAME:

TITLE_REC:
  .byte 0, 0, 32, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01   ; bordo grigio
  .byte 1, 0, 32, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01   ; bordo grigio
  .byte 22, 0, 32, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01   ; bordo grigio
  .byte 23, 0, 32, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01   ; bordo grigio
  .byte 3, 10, 12, $D0, $D1, $AC, $AD, $F0, $F1, $C0, $C1, $D0, $D1, $B8, $B9   ; DAVIDE
  .byte 4, 10, 12, $D2, $D3, $AE, $AF, $F2, $F3, $C2, $C3, $D2, $D3, $BA, $BB   ; DAVIDE
  .byte 6, 9, 14, $F0, $F1, $E8, $E9, $00, $00, $B8, $B9, $C4, $C5, $C0, $C1, $AC, $AD   ; VS ELIA
  .byte 7, 9, 14, $F2, $F3, $EA, $EB, $00, $00, $BA, $BB, $C6, $C7, $C2, $C3, $AE, $AF   ; VS ELIA
  .byte 9, 8, 15, $4A, $4F, $59, $53, $54, $49, $43, $4B, $20, $3D, $20, $4D, $4F, $56, $45   ; JOYSTICK = MOVE
  .byte 11, 5, 22, $42, $55, $54, $54, $4F, $4E, $20, $3D, $20, $53, $48, $4F, $4F, $54, $20, $4F, $52, $20, $4A, $55, $4D, $50   ; BUTTON = SHOOT OR JUMP
  .byte 13, 3, 25, $42, $45, $59, $4F, $4E, $44, $20, $54, $48, $45, $20, $41, $52, $43, $20, $3D, $20, $33, $20, $50, $4F, $49, $4E, $54, $53   ; BEYOND THE ARC = 3 POINTS
  .byte 15, 8, 16, $46, $49, $52, $53, $54, $20, $54, $4F, $20, $32, $31, $20, $57, $49, $4E, $53   ; FIRST TO 21 WINS
  .byte $FF

TITLE_PRESS:
  .byte 19, 9, 14, $50, $52, $45, $53, $53, $20, $41, $20, $42, $55, $54, $54, $4F, $4E   ; PRESS A BUTTON
  .byte $FF

END_REC:
  .byte 3, 8, 16, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00   ; pannello nero
  .byte 4, 8, 16, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00   ; pannello nero
  .byte 5, 8, 16, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00   ; pannello nero
  .byte 6, 8, 16, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00   ; pannello nero
  .byte 7, 8, 16, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00   ; pannello nero
  .byte 8, 8, 16, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00   ; pannello nero
  .byte 9, 8, 16, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00   ; pannello nero
  .byte 10, 8, 16, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00   ; pannello nero
  .byte 2, 6, 20, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00   ; cancella il messaggio
  .byte $FF

END_PRESS:
  .byte 9, 9, 14, $50, $52, $45, $53, $53, $20, $41, $20, $42, $55, $54, $54, $4F, $4E   ; PRESS A BUTTON
  .byte $FF

BANNER_D:
  .byte 3, 10, 12, $D0, $D1, $AC, $AD, $F0, $F1, $C0, $C1, $D0, $D1, $B8, $B9   ; DAVIDE
  .byte 4, 10, 12, $D2, $D3, $AE, $AF, $F2, $F3, $C2, $C3, $D2, $D3, $BA, $BB   ; DAVIDE
  .byte 6, 11, 10, $D8, $D9, $C0, $C1, $B0, $B1, $E8, $E9, $EC, $ED   ; WINS!
  .byte 7, 11, 10, $DA, $DB, $C2, $C3, $B2, $B3, $EA, $EB, $EE, $EF   ; WINS!
  .byte $FF

BANNER_E:
  .byte 3, 12, 8, $B8, $B9, $C4, $C5, $C0, $C1, $AC, $AD   ; ELIA
  .byte 4, 12, 8, $BA, $BB, $C6, $C7, $C2, $C3, $AE, $AF   ; ELIA
  .byte 6, 11, 10, $D8, $D9, $C0, $C1, $B0, $B1, $E8, $E9, $EC, $ED   ; WINS!
  .byte 7, 11, 10, $DA, $DB, $C2, $C3, $B2, $B3, $EA, $EB, $EE, $EF   ; WINS!
  .byte $FF

; messaggi sulla riga 2 (20 caratteri, centrati); indice = MSG_* nel codice
MSG_TAB:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00   ; 0: (vuoto)
  .byte $00,$00,$00,$42,$41,$4C,$4C,$00,$54,$4F, $00, $44, $41, $56, $49, $44, $45, $00, $00, $00   ; 1: BALL TO DAVIDE
  .byte $00,$00,$00,$00,$42,$41,$4C,$4C,$00,$54, $4F, $00, $45, $4C, $49, $41, $00, $00, $00, $00   ; 2: BALL TO ELIA
  .byte $00,$00,$32,$2D,$50,$4F,$49,$4E,$54,$00, $42, $41, $53, $4B, $45, $54, $21, $00, $00, $00   ; 3: 2-POINT BASKET!
  .byte $00,$00,$33,$2D,$50,$4F,$49,$4E,$54,$00, $42, $41, $53, $4B, $45, $54, $21, $00, $00, $00   ; 4: 3-POINT BASKET!
  .byte $00,$00,$00,$00,$00,$00,$00,$42,$4C,$4F, $43, $4B, $21, $00, $00, $00, $00, $00, $00, $00   ; 5: BLOCK!
  .byte $00,$00,$00,$00,$42,$41,$4C,$4C,$00,$53, $54, $4F, $4C, $45, $4E, $21, $00, $00, $00, $00   ; 6: BALL STOLEN!

; ---- tabelle del sonoro ----
V0_TAB:        .byte 13, 9, 12, 0      ; volume all'attacco della nota
FLOOR_TAB:     .byte 9, 4, 8, 0        ; volume minimo raggiunto dal decadimento
DECMASK_TAB:   .byte 7, 3, 3, 0        ; il volume cala di 1 quando (eta' AND maschera) = 0
VIB_TAB:       .byte 0, 1, 1, 0, 0, $FF, $FF, 0   ; vibrato +-1 passo (signed)
; batteria: 1 cassa, 2 rullante, 3 charleston, 4 piatto
DRUM_NP:       .byte 0, 28, 10, 2, 5
DRUM_V0:       .byte 0, 15, 14, 8, 15
DRUM_MASK:     .byte 0, 0, 0, 0, 7

; periodi AY (1 MHz): TP = 62500 / f.  indice = nota MIDI - 35  (1 = C2 ... 55 = F#6), 0 = pausa
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

SONGP_LO:      .byte <TITLE_LEAD,<TITLE_HARM,<TITLE_BASS,<TITLE_DRUM,<WIN_LEAD,<WIN_HARM,<WIN_BASS,<WIN_DRUM
SONGP_HI:      .byte >TITLE_LEAD,>TITLE_HARM,>TITLE_BASS,>TITLE_DRUM,>WIN_LEAD,>WIN_HARM,>WIN_BASS,>WIN_DRUM

; canzoni originali: .byte nota, durata (frame); $FF = fine traccia (nota = MIDI - 35, 0 = pausa)
TITLE_LEAD:
  .byte $29,$0F,$2C,$0F,$31,$1E,$2C,$0F,$29,$0F,$2C,$1E,$27,$0F,$2C,$0F
  .byte $30,$1E,$2C,$0F,$27,$0F,$2C,$1E,$29,$0F,$2E,$0F,$31,$1E,$2E,$0F
  .byte $29,$0F,$2E,$1E,$2A,$0F,$2E,$0F,$31,$1E,$2E,$0F,$2A,$0F,$2C,$1E
  .byte $2C,$1E,$29,$0F,$2C,$0F,$31,$3C,$30,$1E,$2C,$0F,$30,$0F,$33,$3C
  .byte $2E,$1E,$2A,$0F,$2E,$0F,$2C,$1E,$30,$1E,$31,$1E,$2C,$0F,$29,$0F
  .byte $25,$3C,$31,$78
  .byte $FF
TITLE_HARM:
  .byte $19,$0F,$1D,$0F,$20,$0F,$1D,$0F,$19,$0F,$1D,$0F,$20,$0F,$1D,$0F
  .byte $14,$0F,$18,$0F,$1B,$0F,$18,$0F,$14,$0F,$18,$0F,$1B,$0F,$18,$0F
  .byte $16,$0F,$19,$0F,$1D,$0F,$19,$0F,$16,$0F,$19,$0F,$1D,$0F,$19,$0F
  .byte $12,$0F,$16,$0F,$19,$0F,$16,$0F,$12,$0F,$16,$0F,$19,$0F,$16,$0F
  .byte $19,$0F,$1D,$0F,$20,$0F,$1D,$0F,$19,$0F,$1D,$0F,$20,$0F,$1D,$0F
  .byte $14,$0F,$18,$0F,$1B,$0F,$18,$0F,$14,$0F,$18,$0F,$1B,$0F,$18,$0F
  .byte $12,$0F,$16,$0F,$19,$0F,$16,$0F,$14,$0F,$18,$0F,$1B,$0F,$18,$0F
  .byte $19,$0F,$1D,$0F,$20,$0F,$1D,$0F,$19,$0F,$1D,$0F,$20,$0F,$1D,$0F
  .byte $1D,$78
  .byte $FF
TITLE_BASS:
  .byte $0D,$1E,$0D,$1E,$14,$1E,$0D,$1E,$08,$1E,$08,$1E,$0F,$1E,$08,$1E
  .byte $0A,$1E,$0A,$1E,$11,$1E,$0A,$1E,$06,$1E,$06,$1E,$0D,$1E,$06,$1E
  .byte $0D,$1E,$0D,$1E,$14,$1E,$0D,$1E,$08,$1E,$08,$1E,$0F,$1E,$08,$1E
  .byte $06,$1E,$06,$1E,$08,$1E,$0F,$1E,$0D,$1E,$0D,$1E,$14,$1E,$0D,$1E
  .byte $0D,$78
  .byte $FF
TITLE_DRUM:
  .byte $01,$0F,$03,$0F,$02,$0F,$03,$0F,$01,$0F,$03,$0F,$02,$0F,$03,$0F
  .byte $01,$0F,$03,$0F,$02,$0F,$03,$0F,$01,$0F,$03,$0F,$02,$0F,$03,$0F
  .byte $01,$0F,$03,$0F,$02,$0F,$03,$0F,$01,$0F,$03,$0F,$02,$0F,$03,$0F
  .byte $01,$0F,$03,$0F,$02,$0F,$03,$0F,$01,$0F,$03,$0F,$02,$0F,$03,$0F
  .byte $01,$0F,$03,$0F,$02,$0F,$03,$0F,$01,$0F,$03,$0F,$02,$0F,$03,$0F
  .byte $01,$0F,$03,$0F,$02,$0F,$03,$0F,$01,$0F,$03,$0F,$02,$0F,$03,$0F
  .byte $01,$0F,$03,$0F,$02,$0F,$03,$0F,$01,$0F,$03,$0F,$02,$0F,$03,$0F
  .byte $01,$0F,$03,$0F,$02,$0F,$03,$0F,$01,$0F,$03,$0F,$02,$0F,$03,$0F
  .byte $04,$78
  .byte $FF
WIN_LEAD:
  .byte $2C,$0C,$2C,$0C,$31,$18,$30,$0C,$2E,$0C,$2C,$18,$2E,$0C,$2E,$0C
  .byte $31,$18,$2E,$0C,$2A,$0C,$2E,$18,$30,$0C,$30,$0C,$33,$18,$30,$0C
  .byte $2C,$0C,$30,$18,$31,$30,$2C,$18,$29,$18,$35,$18,$31,$0C,$2E,$0C
  .byte $31,$18,$35,$18,$36,$18,$31,$0C,$2E,$0C,$31,$18,$2A,$18,$33,$18
  .byte $30,$0C,$2C,$0C,$30,$18,$33,$18,$31,$0C,$35,$0C,$31,$0C,$35,$0C
  .byte $31,$30,$31,$60
  .byte $FF
WIN_HARM:
  .byte $19,$0C,$1D,$0C,$20,$0C,$1D,$0C,$19,$0C,$1D,$0C,$20,$0C,$1D,$0C
  .byte $1E,$0C,$22,$0C,$25,$0C,$22,$0C,$1E,$0C,$22,$0C,$25,$0C,$22,$0C
  .byte $20,$0C,$24,$0C,$27,$0C,$24,$0C,$20,$0C,$24,$0C,$27,$0C,$24,$0C
  .byte $19,$0C,$1D,$0C,$20,$0C,$1D,$0C,$19,$0C,$1D,$0C,$20,$0C,$1D,$0C
  .byte $22,$0C,$25,$0C,$29,$0C,$25,$0C,$22,$0C,$25,$0C,$29,$0C,$25,$0C
  .byte $1E,$0C,$22,$0C,$25,$0C,$22,$0C,$1E,$0C,$22,$0C,$25,$0C,$22,$0C
  .byte $20,$0C,$24,$0C,$27,$0C,$24,$0C,$20,$0C,$24,$0C,$27,$0C,$24,$0C
  .byte $19,$0C,$1D,$0C,$20,$0C,$1D,$0C,$19,$0C,$1D,$0C,$20,$0C,$1D,$0C
  .byte $1D,$60
  .byte $FF
WIN_BASS:
  .byte $0D,$18,$0D,$18,$14,$18,$0D,$18,$12,$18,$12,$18,$19,$18,$12,$18
  .byte $14,$18,$14,$18,$1B,$18,$14,$18,$0D,$18,$0D,$18,$14,$18,$0D,$18
  .byte $16,$18,$16,$18,$1D,$18,$16,$18,$12,$18,$12,$18,$19,$18,$12,$18
  .byte $14,$18,$14,$18,$1B,$18,$14,$18,$0D,$18,$0D,$18,$14,$18,$0D,$18
  .byte $0D,$60
  .byte $FF
WIN_DRUM:
  .byte $01,$0C,$03,$0C,$02,$0C,$03,$0C,$01,$0C,$03,$0C,$02,$0C,$03,$0C
  .byte $01,$0C,$03,$0C,$02,$0C,$03,$0C,$01,$0C,$03,$0C,$02,$0C,$03,$0C
  .byte $01,$0C,$03,$0C,$02,$0C,$03,$0C,$01,$0C,$03,$0C,$02,$0C,$03,$0C
  .byte $01,$0C,$03,$0C,$02,$0C,$03,$0C,$01,$0C,$03,$0C,$02,$0C,$03,$0C
  .byte $01,$0C,$03,$0C,$02,$0C,$03,$0C,$01,$0C,$03,$0C,$02,$0C,$03,$0C
  .byte $01,$0C,$03,$0C,$02,$0C,$03,$0C,$01,$0C,$03,$0C,$02,$0C,$03,$0C
  .byte $01,$0C,$03,$0C,$02,$0C,$03,$0C,$01,$0C,$03,$0C,$02,$0C,$03,$0C
  .byte $01,$0C,$03,$0C,$02,$0C,$03,$0C,$01,$0C,$03,$0C,$02,$0C,$03,$0C
  .byte $04,$60
  .byte $FF

; gridi: tre "whoo!" che salgono di tono (112 frame, un passo ogni 2 frame)
CHEER_V:
  .byte $04,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D
  .byte $0D,$09,$04,$00,$00,$00,$04,$0D,$0D,$0D,$0D,$0D,$0D,$0D
  .byte $0D,$0D,$0D,$0D,$0D,$0D,$0D,$09,$04,$00,$00,$00,$04,$0D
  .byte $0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$0D,$09,$04
CHEER_TL:
  .byte $B3,$A5,$9D,$97,$91,$8C,$84,$81,$81,$7F,$78,$72,$70,$71
  .byte $6F,$6A,$65,$9C,$9C,$9C,$A4,$98,$90,$8A,$85,$80,$79,$77
  .byte $76,$74,$6E,$69,$67,$67,$65,$61,$5C,$9C,$9C,$9C,$95,$87
  .byte $7F,$79,$73,$6F,$68,$65,$64,$61,$5C,$57,$55,$55,$53,$4F
CHEER_TH:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
CHEER_CTL:
  .byte $77,$6E,$69,$64,$61,$5D,$58,$56,$56,$55,$50,$4C,$4B,$4B
  .byte $4A,$47,$43,$68,$68,$68,$6E,$65,$60,$5C,$59,$56,$51,$4F
  .byte $4F,$4D,$49,$46,$44,$45,$44,$40,$3D,$68,$68,$68,$63,$5A
  .byte $55,$51,$4D,$4A,$45,$43,$43,$41,$3D,$3A,$39,$38,$37,$34
CHEER_CTH:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00

; effetti: inizio di ogni effetto nelle tabelle EV* (1 = SCORE, 2 = MISS, 3 = BLOCK, 4 = STEAL)
EVT_OFF:
  .byte $00,$00,$2C,$48,$58
; durata (frame)
EVT_LEN:
  .byte $00,$2C,$1C,$10,$16
; ritardo dell'applauso dopo l'effetto (0 = nessun applauso)
EVT_ADLY:
  .byte $00,$1A,$00,$08,$0C
; canale A: volume / periodo
EVA_V:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$0D,$0D,$0C,$0C,$0B,$0B,$0A,$0A
  .byte $0D,$0D,$0C,$0C,$0B,$0B,$0A,$0A,$0D,$0D,$0C,$0C,$0B,$0B,$0A,$0A
  .byte $0E,$0D,$0D,$0C,$0B,$0A,$09,$08,$06,$04,$02,$01,$0B,$0A,$09,$08
  .byte $07,$06,$05,$04,$03,$02,$06,$05,$04,$04,$03,$03,$02,$02,$01,$01
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$0D,$09,$05,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$0C,$0C
  .byte $0B,$0B,$0A,$09,$0D,$0D,$0C,$0C,$0B,$0A,$08,$05,$00,$00
EVA_TL:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$50,$50,$50,$50,$50,$50,$50,$50
  .byte $3C,$3C,$3C,$3C,$3C,$3C,$3C,$3C,$2F,$2F,$2F,$2F,$2F,$2F,$2F,$2F
  .byte $28,$28,$28,$28,$28,$28,$28,$28,$28,$28,$28,$28,$2A,$2A,$2A,$2A
  .byte $2A,$2A,$2A,$2A,$2A,$2A,$35,$35,$35,$35,$35,$35,$35,$35,$35,$35
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$45,$45,$45,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$59,$59
  .byte $59,$59,$59,$59,$39,$39,$39,$39,$39,$39,$39,$39,$00,$00
EVA_TH:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
; rumore (canale B): volume / periodo
EVN_V:
  .byte $03,$06,$09,$0B,$0C,$0C,$0B,$0A,$08,$06,$05,$03,$02,$01,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$0C,$09,$05,$02
  .byte $00,$00,$00,$00,$00,$00,$05,$03,$01,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$0F,$0E,$0C,$0A,$08,$06,$04,$03
  .byte $02,$01,$00,$00,$00,$00,$00,$00,$04,$07,$09,$0A,$0A,$09,$07,$05
  .byte $03,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
EVN_P:
  .byte $06,$07,$07,$08,$08,$09,$09,$0A,$0A,$0B,$0B,$0C,$0C,$0D,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$02,$02,$02,$02
  .byte $00,$00,$00,$00,$00,$00,$03,$03,$03,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$04,$04,$05,$05,$05,$06,$06,$06
  .byte $07,$07,$00,$00,$00,$00,$00,$00,$03,$04,$05,$06,$07,$08,$09,$0A
  .byte $0B,$0C,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
; canale C (colpo basso): volume / periodo
EVC_V:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$0D,$0C,$0B,$09
  .byte $08,$06,$05,$04,$03,$02,$02,$01,$01,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$0E,$0D,$0B,$09,$07,$05,$03,$02
  .byte $01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
EVC_TL:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$49,$50,$57,$5D
  .byte $64,$6B,$72,$78,$7F,$86,$8D,$93,$9A,$A1,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$A1,$AD,$B8,$C4,$CF,$DB,$E6,$F2
  .byte $FD,$09,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
EVC_TH:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$01,$01,$01
  .byte $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$01,$01,$01,$01,$01,$01,$01,$01
  .byte $01,$02,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
; palleggio: tonfo di 6 frame sul canale C del chip del giocatore
DRIB_V:
  .byte $0D,$0B,$08,$05,$03,$01
DRIB_TL:
  .byte $38,$7E,$C4,$0B,$51,$97
DRIB_TH:
  .byte $02,$02,$02,$03,$03,$03
; applauso: inviluppo (un valore ogni 8 frame, 96 frame in tutto)
APPL_ENV:
  .byte $05,$09,$0C,$0D,$0E,$0E,$0E,$0D,$0C,$0A,$08,$06,$03
; applauso finale: inviluppo (un valore ogni 16 frame, 150 frame in tutto)
CAPPL_ENV:
  .byte $07,$0B,$0E,$0F,$0F,$0F,$0F,$0E,$0C,$09

