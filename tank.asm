;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;                                                              ;
;   ARCADE_001  -  Tank vs Tank, 2 giocatori, TMS9918A G2     ;
;   Written in 65C02 assembly                                  ;
;   Base: arcade_IRQ_move_SPRITE_009 (NMI/vblank + SAT buffer) ;
;   Pattern: arcade_PATTERN_003 (campo verde)                  ;
;                                                              ;
;   - verde (tile 01) = zona percorribile, il resto e' muro    ;
;   - P1 su PORTA ($D581), P2 su PORTB ($D580), stessi bit:    ;
;       bit2/bit3 = ruota, bit4 = avanti, bit5 = fuoco         ;
;   - un colpo a segno = 1 punto, vince chi arriva a WIN_SCORE ;
;   - schermata START e schermata FINE con vincitore           ;
;   - SONORO (2 x AY-3-8910): The Final Countdown al titolo,     ;
;     sparo, esplosione, motore, fanfara di vittoria           ;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; ---------------- zero page (usate dal pattern/VDP) ----------------
VDP_INIT                 = $30
VDP_INIT_HI              = $31
FREEZE_COLOR             = $3A
VDP_INIT_A               = $40
VDP_INIT_HI_A            = $41

; ---------------- zero page: dati dei due giocatori ----------------
; ogni voce occupa 2 byte: indice X = 0 (P1) oppure 1 (P2)
P_X                      = $60     ; X sprite del tank
P_Y                      = $62     ; Y sprite del tank (valore SAT: riga visibile = Y+1)
P_DIR                    = $64     ; 0=UP 1=UP-RG 2=RG 3=RG-DW 4=DW 5=DW-LF 6=LF 7=LF-UP
P_JOY                    = $66     ; joystick, 1 = premuto
P_MCNT                   = $68     ; contatore velocita' tank
P_ROT                    = $6A     ; ritardo rotazione
B_ACT                    = $6C     ; proiettile: 0 = fermo, 1 = in volo
B_X                      = $6E
B_Y                      = $70
B_DIR                    = $72
P_SCORE                  = $74     ; punteggio

; ---------------- zero page: stato di gioco e temporanee ----------------
EXPL_TIMER               = $76     ; >0 = esplosione in corso (frame rimasti)
VICTIM                   = $77     ; chi e' stato colpito
SHOOTER                  = $78     ; chi ha sparato il colpo a segno
WINNER                   = $79     ; vincitore della partita
HUD_DIRTY                = $7A     ; 1 = ridisegna il punteggio
ARMED                    = $7B     ; schermata fine: pulsante accettato
GO_DELAY                 = $7C     ; schermata fine: attesa minima
SPIN_CNT                 = $7D
CK_PL                    = $7E     ; giocatore che sta muovendo (per CHECK_FREE)
BS_SH                    = $7F     ; sparatore (per BULLET_STEP)
TX                       = $80     ; posizione candidata del tank
TY                       = $81
LK_X                     = $82     ; punto in pixel da cercare nella name table
LK_Y                     = $83
LK_ROW                   = $84
LK_HI                    = $85
LK_PTR                   = $86     ; 2 byte
PTR                      = $88     ; 2 byte: puntatore ai record delle schermate
T0                       = $8A
T1                       = $8B
T2                       = $8C
T3                       = $8D

PORTB_JOY = $d580        ;         |P2|P1|RG|LF|DW|UP (LSB)   joystick 2
PORTA_JOY = $d581        ;         |P2|P1|RG|LF|DW|UP (LSB)   joystick 1
DDRB_JOY  = $d582        ;
DDRA_JOY  = $d583        ;
ACR_JOY   = $d58B

; ---------------- sonoro: due AY-3-8910, clock 1 MHz ----------------
AY_R_LATCH = $D380       ; AY destro  (tank 2)
AY_R_WRITE = $D381
AY_L_LATCH = $D384       ; AY sinistro (tank 1)
AY_L_WRITE = $D385

SH_L       = $A0         ; shadow registri AY sinistro 0-10  (11 byte)
SH_R       = $B0         ; shadow registri AY destro   0-10  (SH_R = SH_L + 16)
SND_CMD    = $C0         ; comando al motore sonoro (CMD_*), eseguito dall'NMI
SND_MODE   = $C1         ; 0 = effetti di gioco, 1 = musica
SND_BUSY   = $C2         ; 1 finche' la canzone sta suonando
SFX_EXPL   = $C3         ; esplosione: frame trascorsi (0 = spenta)
SFX_SHOT   = $C4         ; sparo: 2 byte (tank 1 / tank 2), frame trascorsi
SND_MV     = $C6         ; 2 byte: 1 = il tank si muove / ruota
SND_PH     = $C8         ; fase (conta i frame)
SND_RND    = $C9
SN0        = $CA         ; temporanei del sonoro
SN1        = $CB
SND_T1     = $CC
TR_PL      = $D0         ; 4 tracce: puntatore (lo / hi), contatore, attiva,
TR_PH      = $D4         ;           nota, volume, eta' della nota
TR_CT      = $D8
TR_ACT     = $DC
TR_NOTE    = $E0
TR_VOL     = $E4
TR_AGE     = $E8
SND_PTR    = $EC         ; 2 byte

CMD_GAME   = 1           ; silenzio + effetti di gioco
CMD_TITLE  = 2           ; The Final Countdown
CMD_WIN    = 3           ; fanfara di vittoria
ENG_VOL    = 4           ; volume del motore (0 = nessun rumore di movimento)
ENG_NVOL   = 2           ; volume del velo di rumore dei cingoli
SHOT_LEN   = 12          ; durata del suono dello sparo (frame)
EXPL_SND_LEN = 60        ; durata del suono dell'esplosione (frame)

; ---------------- parametri di gioco ----------------
WIN_SCORE   = 5          ; punti per vincere (max 9: ci sono le cifre grandi 0-9)
MOVE_SPEED  = $01        ; frame (NMI) tra un passo e l'altro del tank
ROT_DELAY   = $02        ; passi MOVE_SPEED tra due rotazioni di 45 gradi
EXPL_FRAMES = 60         ; durata esplosione in frame
HIDE_Y      = $C0        ; Y fuori schermo (NON $D0: fermerebbe la lista sprite)
BTN_MASK    = %00110000  ; pulsanti accettati per START / CONTINUA
TILE_GREEN  = $01        ; tile percorribile

; posizioni di partenza (punto-simmetriche: P2 = ribaltato di 180 gradi rispetto a P1)
P1_START_X   = 72
P1_START_Y   = 15
P1_START_DIR = 4
P2_START_X   = 168
P2_START_Y   = 159
P2_START_DIR = 0

; tile grandi (generati: vedi VDP_PATTERNS in fondo)
BIG0         = $80      ; cifre 0-9: 4 tile ciascuna
COL_DIGITS   = $B1           ; giallo su nero
COL_LETTERS  = $91           ; rosso chiaro su nero


 .org $0FD0               ; trampolino chiamato da NMI_HANDLER (bios) con JSR $0FD0
DISPATCH:
  JMP NMI_TASK


 .org $1000
VREG  = $B001                ;VDP REGISTER
VDATA = $B000                ;VDP RAM


VDP_NAME_TABLE_BASE    = $3800      ; NAME TABLE    OK REG2      0E
VDP_COLOR_TABLE_BASE   = $2000      ; COLOR TABLE   OK REG3      80
VDP_PATTERN_TABLE_BASE = $0000      ; PATTERN TABLE OK REG4      00
VDP_SPRITE_ATT_BASE    = $3B00      ; SPRITE ATT    OK REG5      78
VDP_SPRITE_TABLE_BASE  = $1800      ; SPRITE TABLE  OK REG6      03 

VDP_WRITE_VRAM_BIT     = %01000000  ; pattern of second vram address write: 01AAAAAA
VDP_REGISTER_BITS      = %10000000  ; pattern of second register write: 10000RRR

RESET:
  JSR VDP_SET_REGISTERS        ; Setting VDP register
  JSR CLEAR_VRAM
  JSR VDP_SETUP
  JSR SND_INIT                 ; AY a zero (l'interrupt VDP e' ancora spento)

  ; joystick: PORTA e PORTB in input
  LDA #$00
  STA DDRA_JOY
  STA DDRB_JOY

  LDA #$00
  STA SPIN_CNT
  STA P_SCORE
  STA P_SCORE+1
  STA EXPL_TIMER
  STA HUD_DIRTY
  JSR HIDE_SPRITES

  ; abilita l'interrupt del VDP (R1: 16K + display ON + INT ON = $E6)
  ; fatto qui, a setup finito, cosi' l'NMI non interrompe CLEAR_VRAM/VDP_SETUP
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
  ; i due tank si guardano ai lati del titolo
  LDA #39
  STA SAT_BUFFER+8
  LDA #28
  STA SAT_BUFFER+9
  LDA #(2*4)                   ; tank P1 verso destra
  STA SAT_BUFFER+10
  LDA #$05
  STA SAT_BUFFER+11
  LDA #39
  STA SAT_BUFFER+12
  LDA #212
  STA SAT_BUFFER+13
  LDA #(6*4)                   ; tank P2 verso sinistra
  STA SAT_BUFFER+14
  LDA #$09
  STA SAT_BUFFER+15
  LDA #$01                     ; parte la canzone: il pulsante si legge solo alla fine
  STA SND_BUSY
  LDA #CMD_TITLE
  STA SND_CMD
.t_song:
  JSR WAIT_FRAME
  LDA SND_BUSY
  BNE .t_song
  JSR VDP_INT_OFF              ; canzone finita: compare "PRESS FIRE TO START"
  LDA #<TITLE_PRESS
  STA PTR
  LDA #>TITLE_PRESS
  STA PTR+1
  JSR DRAW_RECORDS
  JSR VDP_INT_ON
  JSR WAIT_FIRE
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
  JSR RESET_ROUND
  JSR HIDE_SPRITES
  JSR VDP_INT_OFF
  JSR LOAD_GAME_NAME_TABLE     ; scritte PLAYER 1 / PLAYER 2 + campo verde
  JSR DRAW_HUD                 ; punteggi grandi sotto le scritte
  JSR VDP_INT_ON
  JSR DRAW_ALL

GAME_LOOP:
  JSR READ_JOY
  LDA EXPL_TIMER
  BNE .gl_expl
  LDX #0
  JSR UPDATE_PLAYER
  LDX #1
  JSR UPDATE_PLAYER
  LDX #0
  JSR UPDATE_BULLET
  LDX #1
  JSR UPDATE_BULLET
  BRA .gl_draw
.gl_expl:
  DEC EXPL_TIMER               ; esplosione in corso: il gioco e' fermo
  BNE .gl_draw
  JSR ROUND_END                ; fine esplosione: nuovo round o fine partita
.gl_draw:
  JSR DRAW_ALL
  JSR WAIT_FRAME               ; sincronizza il loop al vblank (NMI)
  LDA HUD_DIRTY
  BEQ GAME_LOOP
  LDA #$00
  STA HUD_DIRTY
  JSR UPDATE_HUD
  BRA GAME_LOOP


; ---------------------------------------------------------------
; fine esplosione: se lo sparatore ha raggiunto WIN_SCORE finisce
; la partita, altrimenti si riparte con i tank alle posizioni iniziali
; ---------------------------------------------------------------
ROUND_END:
  LDX SHOOTER
  LDA P_SCORE,X
  CMP #WIN_SCORE
  BCC .re_next
  STX WINNER
  JMP GAME_OVER
.re_next:
  JSR RESET_ROUND
  RTS

RESET_ROUND:
  LDA #P1_START_X
  STA P_X
  LDA #P1_START_Y
  STA P_Y
  LDA #P1_START_DIR
  STA P_DIR
  LDA #P2_START_X
  STA P_X+1
  LDA #P2_START_Y
  STA P_Y+1
  LDA #P2_START_DIR
  STA P_DIR+1
  LDA #$00
  STA P_MCNT
  STA P_MCNT+1
  STA P_ROT
  STA P_ROT+1
  STA B_ACT
  STA B_ACT+1
  STA EXPL_TIMER
  RTS


; ---------------------------------------------------------------
; legge i due joystick (1 = premuto)
; ---------------------------------------------------------------
READ_JOY:
  LDA PORTA_JOY
  EOR #$FF
  STA P_JOY
  LDA PORTB_JOY
  EOR #$FF
  STA P_JOY+1
  RTS


; ---------------------------------------------------------------
; aggiorna un tank: X = giocatore (0/1)
; ---------------------------------------------------------------
UPDATE_PLAYER:
  LDA P_JOY,X                   ; flag per il rumore del motore: ruota o avanza
  AND #%00011100
  BEQ .up_mv                    ; A = 0
  LDA #$01
.up_mv:
  STA SND_MV,X
  LDA P_JOY,X
  AND #%00111100                ; isola rotazione, avanti, fuoco
  BNE .up_keys
  LDA #$00
  STA P_MCNT,X
  RTS
.up_keys:
  INC P_MCNT,X
  LDA P_MCNT,X
  CMP #MOVE_SPEED
  BCC .up_done                  ; non ancora tempo per il tank
  LDA #$00
  STA P_MCNT,X
  LDA P_ROT,X                   ; rotazione limitata da ROT_DELAY
  BEQ .up_rot_ready
  DEC P_ROT,X
  BRA .up_fire
.up_rot_ready:
  LDA P_JOY,X                   ; bit 2: ruota antiorario
  AND #%00000100
  BEQ .up_left
  LDA P_DIR,X
  SEC
  SBC #1
  AND #$07
  STA P_DIR,X
  LDA #ROT_DELAY
  STA P_ROT,X
  BRA .up_fire
.up_left:
  LDA P_JOY,X                   ; bit 3: ruota orario
  AND #%00001000
  BEQ .up_fire
  LDA P_DIR,X
  CLC
  ADC #1
  AND #$07
  STA P_DIR,X
  LDA #ROT_DELAY
  STA P_ROT,X
.up_fire:
  LDA P_JOY,X                   ; bit 5: fuoco
  AND #%00100000
  BEQ .up_move
  LDA B_ACT,X                   ; un solo colpo in volo alla volta
  BNE .up_move
  LDA #$01
  STA B_ACT,X
  LDA P_X,X
  STA B_X,X
  LDA P_Y,X
  STA B_Y,X
  LDA P_DIR,X
  STA B_DIR,X
  LDA #$01                      ; suono dello sparo
  STA SFX_SHOT,X
.up_move:
  LDA P_JOY,X                   ; bit 4: avanti
  AND #%00010000
  BEQ .up_done
  JSR MOVE_TANK
.up_done:
  RTS


; ---------------------------------------------------------------
; avanza di 1 pixel nella direzione del tank se il percorso e' libero.
; Sulle diagonali, se il passo e' bloccato prova a scivolare in X o in Y.
; X = giocatore
; ---------------------------------------------------------------
MOVE_TANK:
  STX CK_PL
  LDY P_DIR,X
  LDA P_X,X
  CLC
  ADC DELTA_X,Y
  STA TX
  LDA P_Y,X
  CLC
  ADC DELTA_Y,Y
  STA TY
  JSR CHECK_FREE
  BCC .mv_ok
  LDA DELTA_X,Y                 ; direzione dritta: niente scivolamento
  BEQ .mv_end
  LDA DELTA_Y,Y
  BEQ .mv_end
  LDA P_X,X                     ; prova solo X
  CLC
  ADC DELTA_X,Y
  STA TX
  LDA P_Y,X
  STA TY
  JSR CHECK_FREE
  BCC .mv_ok
  LDA P_X,X                     ; prova solo Y
  STA TX
  LDA P_Y,X
  CLC
  ADC DELTA_Y,Y
  STA TY
  JSR CHECK_FREE
  BCS .mv_end
.mv_ok:
  LDA TX
  STA P_X,X
  LDA TY
  STA P_Y,X
.mv_end:
  RTS


; ---------------------------------------------------------------
; la posizione candidata (TX,TY) e' libera?
; Hitbox del tank 12x12: X+2..X+13, righe visibili Y+3..Y+14.
; Si controllano 3x3 punti (passo <= 6 px < 8 px di tile): nessun tile
; toccato dall'hitbox puo' sfuggire. Libero = tile verde e nessuna
; sovrapposizione con l'altro tank.
; out: C=0 libero, C=1 bloccato. Conserva X e Y.
; ---------------------------------------------------------------
CHECK_FREE:
  PHX
  PHY
  LDX #2
.cf_row:
  LDA TY
  CLC
  ADC YOFFS,X
  STA LK_Y
  LDY #2
.cf_col:
  LDA TX
  CLC
  ADC XOFFS,Y
  STA LK_X
  JSR TILE_AT
  CMP #TILE_GREEN
  BNE .cf_blocked
  DEY
  BPL .cf_col
  DEX
  BPL .cf_row
  LDA CK_PL                     ; sovrapposizione con l'altro tank
  EOR #$01
  TAX
  LDA TX
  SEC
  SBC P_X,X
  BCS .cf_dx
  EOR #$FF
  ADC #1
.cf_dx:
  CMP #12
  BCS .cf_free
  LDA TY
  SEC
  SBC P_Y,X
  BCS .cf_dy
  EOR #$FF
  ADC #1
.cf_dy:
  CMP #12
  BCS .cf_free
.cf_blocked:
  SEC
  BRA .cf_end
.cf_free:
  CLC
.cf_end:
  PLY
  PLX
  RTS


; ---------------------------------------------------------------
; tile della name table sotto il pixel (LK_X, LK_Y) -> A
; (legge la copia della name table in RAM: VDP_NAME). Conserva X e Y.
; ---------------------------------------------------------------
TILE_AT:
  LDA LK_Y
  LSR A
  LSR A
  LSR A                         ; riga 0..31
  STA LK_ROW
  LSR A
  LSR A
  LSR A
  STA LK_HI                     ; riga / 8
  LDA LK_ROW
  AND #$07
  ASL A
  ASL A
  ASL A
  ASL A
  ASL A                         ; (riga mod 8) * 32
  STA LK_PTR
  LDA LK_X
  LSR A
  LSR A
  LSR A                         ; colonna
  ORA LK_PTR
  CLC
  ADC #<VDP_NAME
  STA LK_PTR
  LDA LK_HI
  ADC #>VDP_NAME
  STA LK_PTR+1
  LDA (LK_PTR)
  RTS


; ---------------------------------------------------------------
; proiettile: due passi per frame. X = sparatore
; ---------------------------------------------------------------
UPDATE_BULLET:
  LDA EXPL_TIMER
  BNE .ub_end
  LDA B_ACT,X
  BEQ .ub_end
  JSR BULLET_STEP
  BCS .ub_end
  JSR BULLET_STEP
.ub_end:
  RTS

; un passo di 1 px. C=1 se il proiettile e' finito (muro o colpito)
BULLET_STEP:
  LDY B_DIR,X
  LDA B_X,X
  CLC
  ADC DELTA_X,Y
  STA B_X,X
  LDA B_Y,X
  CLC
  ADC DELTA_Y,Y
  STA B_Y,X
  LDA B_X,X                     ; punto del proiettile = posizione sprite + offset del puntino
  CLC
  ADC DOT_XOFF,Y
  STA LK_X
  LDA B_Y,X
  CLC
  ADC DOT_YOFF,Y
  STA LK_Y
  JSR TILE_AT
  CMP #TILE_GREEN
  BNE .bs_wall                  ; fuori dal verde: il proiettile si ferma
  STX BS_SH
  TXA
  EOR #$01
  TAX                           ; X = avversario
  LDA LK_X
  SEC
  SBC P_X,X
  SEC
  SBC #2
  CMP #12                       ; dentro X+2..X+13 ?
  BCS .bs_miss
  LDA LK_Y
  SEC
  SBC P_Y,X
  SEC
  SBC #3
  CMP #12                       ; dentro Y+3..Y+14 ?
  BCS .bs_miss
  LDX BS_SH                     ; COLPITO
  JSR BULLET_HIT
  SEC
  RTS
.bs_miss:
  LDX BS_SH
  CLC
  RTS
.bs_wall:
  LDA #$00
  STA B_ACT,X
  SEC
  RTS

; X = sparatore: +1 punto, esplosione del bersaglio
BULLET_HIT:
  LDA #$00
  STA B_ACT
  STA B_ACT+1
  INC P_SCORE,X
  STX SHOOTER
  TXA
  EOR #$01
  STA VICTIM
  LDA #EXPL_FRAMES
  STA EXPL_TIMER
  LDA #$01
  STA HUD_DIRTY
  STA SFX_EXPL                  ; suono dell'esplosione
  LDA #$00
  STA SFX_SHOT
  STA SFX_SHOT+1
  STA SND_MV
  STA SND_MV+1
  RTS


; ===============================================================
;  SCHERMATA FINE PARTITA: annuncia il vincitore
; ===============================================================
GAME_OVER:
  LDX #$FF
  TXS
  JSR HIDE_SPRITES
  JSR VDP_INT_OFF
  JSR CLEAR_NAME_TABLE
  LDA #<END_REC
  STA PTR
  LDA #>END_REC
  STA PTR+1
  JSR DRAW_RECORDS
  LDA WINNER                    ; "PLAYER 1" o "PLAYER 2"
  BNE .go_p2
  LDA #<BANNER_1
  STA PTR
  LDA #>BANNER_1
  BRA .go_banner
.go_p2:
  LDA #<BANNER_2
  STA PTR
  LDA #>BANNER_2
.go_banner:
  STA PTR+1
  JSR DRAW_RECORDS
  LDA P_SCORE                   ; punteggio finale con le cifre grandi
  ASL A
  ASL A
  CLC
  ADC #BIG0
  STA T0
  LDA #$C9                      ; riga 14, colonna 9  ($39C9)
  STA T1
  LDA #$79
  STA T2
  JSR DRAW_BIG
  LDA P_SCORE+1
  ASL A
  ASL A
  CLC
  ADC #BIG0
  STA T0
  LDA #$D5                      ; riga 14, colonna 21 ($39D5)
  STA T1
  LDA #$79
  STA T2
  JSR DRAW_BIG
  JSR VDP_INT_ON
  ; il tank del vincitore gira su se' stesso al centro
  LDX WINNER
  LDA #135
  STA SAT_BUFFER+8
  LDA #120
  STA SAT_BUFFER+9
  LDA #$00
  STA SAT_BUFFER+10
  LDA TANK_COLOR,X
  STA SAT_BUFFER+11
  LDA #$01                      ; canzone di vittoria
  STA SND_BUSY
  LDA #CMD_WIN
  STA SND_CMD
  LDA #$00
  STA ARMED
  LDA #120                      ; almeno 2 secondi prima di accettare il pulsante
  STA GO_DELAY
.go_loop:
  JSR WAIT_FRAME
  INC SPIN_CNT
  LDA SPIN_CNT
  AND #$07
  BNE .go_nospin
  LDA SAT_BUFFER+10
  CLC
  ADC #4
  AND #$1F
  STA SAT_BUFFER+10
.go_nospin:
  JSR READ_JOY
  LDA P_JOY
  ORA P_JOY+1
  AND #BTN_MASK
  BNE .go_pressed
  LDA GO_DELAY                  ; pulsanti rilasciati: conta l'attesa, poi arma
  BNE .go_dec
  LDA SND_BUSY                  ; ... ma solo a canzone finita
  BNE .go_loop
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
  CPX #17               ; 4 sprite x 4 byte + Y=$D0 della 5a voce
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

; SAT: ordine di priorita': 0-1 proiettili, 2-3 tank
SAT_BUFFER:    .byte HIDE_Y,$00,$20,$07   ; sprite 0: proiettile P1
               .byte HIDE_Y,$00,$20,$0B   ; sprite 1: proiettile P2
               .byte HIDE_Y,$00,$00,$05   ; sprite 2: tank P1
               .byte HIDE_Y,$00,$00,$09   ; sprite 3: tank P2
               .byte $D0                  ; sprite 4: Y=$D0 = fine lista

HIDE_SPRITES:
  LDA #HIDE_Y
  STA SAT_BUFFER
  STA SAT_BUFFER+4
  STA SAT_BUFFER+8
  STA SAT_BUFFER+12
  RTS

; riempie SAT_BUFFER (solo RAM) dallo stato di gioco
DRAW_ALL:
  LDX #0
.da_loop:
  TXA
  ASL A
  ASL A
  TAY                           ; Y = X*4
  LDA B_ACT,X
  BNE .da_bullet
  LDA #HIDE_Y
  STA SAT_BUFFER,Y
  BRA .da_tank
.da_bullet:
  LDA B_Y,X
  STA SAT_BUFFER,Y
  LDA B_X,X
  STA SAT_BUFFER+1,Y
  LDA B_DIR,X                   ; pattern proiettile = 32 + dir*4
  ASL A
  ASL A
  CLC
  ADC #32
  STA SAT_BUFFER+2,Y
  LDA BULLET_COLOR,X
  STA SAT_BUFFER+3,Y
.da_tank:
  LDA P_Y,X
  STA SAT_BUFFER+8,Y
  LDA P_X,X
  STA SAT_BUFFER+9,Y
  LDA P_DIR,X                   ; pattern tank = dir*4
  ASL A
  ASL A
  STA SAT_BUFFER+10,Y
  LDA TANK_COLOR,X
  STA SAT_BUFFER+11,Y
  LDA EXPL_TIMER                ; il tank colpito diventa un'esplosione
  BEQ .da_next
  CPX VICTIM
  BNE .da_next
  LDA EXPL_TIMER
  AND #$04
  BEQ .da_exp_a
  LDA #68
  STA SAT_BUFFER+10,Y
  LDA #$08
  STA SAT_BUFFER+11,Y
  BRA .da_next
.da_exp_a:
  LDA #64
  STA SAT_BUFFER+10,Y
  LDA #$0B
  STA SAT_BUFFER+11,Y
.da_next:
  INX
  CPX #2
  BNE .da_loop
  RTS

TANK_COLOR:    .byte $05,$09
BULLET_COLOR:  .byte $07,$0B

; punto di campionamento della hitbox (offset dallo sprite) per il controllo muri
XOFFS:         .byte 2,8,13
YOFFS:         .byte 3,9,14
; posizione del puntino del proiettile dentro lo sprite 16x16, per direzione
; (X, e Y gia' +1 perche' il VDP disegna lo sprite alla riga Y+1)
DOT_XOFF:      .byte 8,11,12,11,8,5,3,5
DOT_YOFF:      .byte 4,6,9,12,13,12,9,6


; ---------------------------------------------------------------
; punteggi grandi sotto le scritte PLAYER 1 / PLAYER 2
; (il VDP deve essere "libero": chiamare con VDP_INT_OFF attivo)
; ---------------------------------------------------------------
UPDATE_HUD:
  JSR VDP_INT_OFF
  JSR DRAW_HUD
  JSR VDP_INT_ON
  RTS

DRAW_HUD:
  LDA P_SCORE
  ASL A
  ASL A
  CLC
  ADC #BIG0
  STA T0
  LDA #$43                      ; riga 2, colonna 3 ($3843): sotto "PLAYER 1" (staccato dalla scritta)
  STA T1
  LDA #$78
  STA T2
  JSR DRAW_BIG
  LDA P_SCORE+1
  ASL A
  ASL A
  CLC
  ADC #BIG0
  STA T0
  LDA #$5B                      ; riga 2, colonna 27 ($385B): sotto "PLAYER 2"
  STA T1
  LDA #$78
  STA T2
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
VDP_SETUP:
  JSR VDP_INITIALIZE_COLOR_TABLE
  JSR VDP_INITIALIZE_SPRITE_TABLE
  JSR VDP_INITIALIZE_PATTERN_TABLE
  LDA #BIG0                     ; colori delle cifre grandi
  LDX #40
  LDY #COL_DIGITS
  JSR SET_TILE_COLOR
  LDA #$A8              ; colori delle lettere grandi
  LDX #72
  LDY #COL_LETTERS
  JSR SET_TILE_COLOR
  RTS

; colora X tile a partire da A con il byte colore Y, nei 3 terzi della color table
SET_TILE_COLOR:
  STA T0                        ; primo tile
  STX T1                        ; numero di tile
  STY T2                        ; colore
  LDA #$20
  STA T3                        ; terzo: $20, $28, $30
.stc_third:
  LDA T0
  ASL A
  ASL A
  ASL A                         ; byte basso di tile*8
  STA VREG
  LDA T0
  LSR A
  LSR A
  LSR A
  LSR A
  LSR A                         ; tile/32
  CLC
  ADC T3
  ORA #VDP_WRITE_VRAM_BIT
  STA VREG
  LDX T1
.stc_tile:
  LDY #8
.stc_byte:
  LDA T2
  STA VDATA
  DEY
  BNE .stc_byte
  DEX
  BNE .stc_tile
  LDA T3
  CLC
  ADC #$08
  STA T3
  CMP #$38
  BNE .stc_third
  RTS

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

VDP_INITIALIZE_PATTERN_TABLE:       
  PHA
  PHX

  ; --- THIRD 0 (VRAM Address $0000) ---
  LDA #$00
  STA VREG
  LDA #($00 | VDP_WRITE_VRAM_BIT)
  STA VREG
  JSR COPY_PATTERNS_BLOCK

  ; --- THIRD 1 (VRAM Address $0800) ---
  LDA #$00
  STA VREG
  LDA #($08 | VDP_WRITE_VRAM_BIT)
  STA VREG
  JSR COPY_PATTERNS_BLOCK

  ; --- THIRD 2 (VRAM Address $1000) ---
  LDA #$00
  STA VREG
  LDA #($10 | VDP_WRITE_VRAM_BIT)
  STA VREG
  JSR COPY_PATTERNS_BLOCK

  PLX
  PLA
  RTS

COPY_PATTERNS_BLOCK:
  LDA #<VDP_PATTERNS                      
  STA VDP_INIT_A
  LDA #>VDP_PATTERNS
  STA VDP_INIT_HI_A
.loop:
  LDA (VDP_INIT_A)                  
  STA VDATA                         
  LDA VDP_INIT_A                    
  CLC                               
  ADC #1                            
  STA VDP_INIT_A                    
  LDA #0                            
  ADC VDP_INIT_HI_A                 
  STA VDP_INIT_HI_A                 
  LDA VDP_INIT_A                    
  CMP #<VDP_END_PATTERNS
  BNE .loop        
  LDA VDP_INIT_HI_A                 
  CMP #>VDP_END_PATTERNS
  BNE .loop        
  RTS


VDP_INITIALIZE_COLOR_TABLE:       
  PHA
  PHX

  ; --- THIRD 0 COLORS (VRAM Address $2000) ---
  LDA #$00
  STA VREG
  LDA #($20 | VDP_WRITE_VRAM_BIT)
  STA VREG
  JSR COPY_COLORS_BLOCK

  ; --- THIRD 1 COLORS (VRAM Address $2800) ---
  LDA #$00
  STA VREG
  LDA #($28 | VDP_WRITE_VRAM_BIT)
  STA VREG
  JSR COPY_COLORS_BLOCK

  ; --- THIRD 2 COLORS (VRAM Address $3000) ---
  LDA #$00
  STA VREG
  LDA #($30 | VDP_WRITE_VRAM_BIT)
  STA VREG
  JSR COPY_COLORS_BLOCK

  PLX
  PLA
  RTS

COPY_COLORS_BLOCK:
  PHA
  PHX
  PHY

  LDA #<VDP_COLOR                      
  STA VDP_INIT
  LDA #>VDP_COLOR
  STA VDP_INIT_HI

  ; ultimo byte della tabella = colore "congelato" per tutti i tile successivi
  LDA #<(VDP_END_COLOR-1)
  STA VDP_INIT_A
  LDA #>(VDP_END_COLOR-1)
  STA VDP_INIT_HI_A
  LDA (VDP_INIT_A)
  STA FREEZE_COLOR

  LDX #8
  LDY #0
  
.loop_color:
  LDA VDP_INIT
  CMP #<VDP_END_COLOR
  BNE .do_write
  LDA VDP_INIT_HI
  CMP #>VDP_END_COLOR
  BEQ .freeze

.do_write:
  LDA (VDP_INIT)
  STA VDATA
  LDA VDP_INIT
  CLC
  ADC #1
  STA VDP_INIT
  LDA #0
  ADC VDP_INIT_HI
  STA VDP_INIT_HI
  JMP .count

.freeze:
  LDA FREEZE_COLOR
  STA VDATA

.count:
  DEY
  BNE .loop_color
  DEX
  BNE .loop_color

  PLY
  PLX
  PLA
  RTS

VDP_INITIALIZE_SPRITE_TABLE:       ; Write to VRAM
  PHA
  PHX
  LDA #<(VDP_SPRITE_TABLE_BASE)
  STA VREG
  LDA #(VDP_WRITE_VRAM_BIT | >VDP_SPRITE_TABLE_BASE)
  STA VREG
  LDA #<VDP_SPRITE
  STA VDP_INIT
  LDA #>VDP_SPRITE
  STA VDP_INIT_HI
VDP_SPRITE_TABLE_LOOP:
  LDA (VDP_INIT)
  STA VDATA
  LDA VDP_INIT
  CLC
  ADC #1
  STA VDP_INIT
  LDA #0
  ADC VDP_INIT_HI
  STA VDP_INIT_HI
  LDA VDP_INIT
  CMP #<VDP_END_SPRITE
  BNE VDP_SPRITE_TABLE_LOOP
  LDA VDP_INIT_HI
  CMP #>VDP_END_SPRITE
  BNE VDP_SPRITE_TABLE_LOOP
  PLX
  PLA
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
   LDY #$40				; SETUP VRAM ADDRESS 
   LDA #0
   STA VREG
   STY VREG
   LDX #$C0				; COUNT HIGH
NEXF:
   LDY #0				; COUNT LOW
FILL_:
   LDA #$00

   STA VDATA		   ; WRITE A ZERO TO VRAM
   INY					; NEXT LOC
   BNE FILL_			; KEEP GOING UNTIL PAGE DONE
   INX					; DONE ALL 40 PAGES?
   BNE NEXF				; NO, KEEP GOING
   PLY
   PLX
   PLA
   RTS

ITAB .BYTE $02,$C6,$0E,$FF       ;INITIALIZE G2 MODE
     .BYTE $03,$76,$03,$0E       ;R0=bit 0 LSB: 0 DISABLE EXT VDP; bit 1: 1 GMODE 2 
                                 ;R1=bit 0 LSB: 0 NO MAGNIDUTE; bit 1: 1 SPRITE SIZE 16X16; bit 3 E 4: 1 M1 E M2 =0; bit 5: 0 INT DISABLE; bit 6: 1 ENABLE DISPLAY;bit 7: 1 16K RAM;
                                 ;R2= NAME TABLE BASE ADDRESS HEX       0E * 400 = 3800
                                 ;R3= COLOR TABLE BASE ADDRESS HEX      FF in G2 mode 80 * 40  = 2000
                                 ;R4= PATTERN TABLE BASE ADDRESS HEX    03 in G2 mode 00 * 800 = 0000
                                 ;R5= SPRITE ATT TABLE BASE ADDRESS HEX 76 * 80  = 3B00
                                 ;R6= SPRITE TABLE BASE ADDRESS HEX     03 * 800 = 1800
                                 ;R7= MSB 4 BIT: TEXT COLOR; LSB 4 BIT BACKGROUND COLOR: 0-TRANSPARENT E GRAY


; ---------------------------------------------------------------
; PATTERN TABLE (uguale in tutti e 3 i terzi)
;   tile 00-01 : pieno (nero / verde)      tile 02-06 : linee
;   tile 07-1F : debug                      tile 20-7F : font ASCII
;   tile 80-A7 : cifre grandi 0-9           tile A8-DF : lettere grandi
; ---------------------------------------------------------------
VDP_PATTERNS:
 ; line drawing
   .byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
   .byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
   .byte $00,$00,$00,$F8,$F8,$18,$18,$18 ; ld
   .byte $00,$00,$00,$1F,$1F,$18,$18,$18 ; rd
   .byte $18,$18,$18,$F8,$F8,$00,$00,$00 ; lu
   .byte $18,$18,$18,$1F,$1F,$00,$00,$00 ; ur
   .byte $18,$18,$18,$FF,$FF,$18,$18,$18 ; lurd
 ; <nonsense for debug>
   .byte $07,$07,$07,$07,$07,$07,$07,$00 ; 07
   .byte $08,$08,$08,$08,$08,$08,$08,$00 ; 08
   .byte $09,$09,$09,$09,$09,$09,$09,$00 ; 09
   .byte $0A,$0A,$0A,$0A,$0A,$0A,$0A,$00 ; 0A
   .byte $0B,$0B,$0B,$0B,$0B,$0B,$0B,$00 ; 0B
   .byte $0C,$0C,$0C,$0C,$0C,$0C,$0C,$00 ; 0C
   .byte $0D,$0D,$0D,$0D,$0D,$0D,$0D,$00 ; 0D
   .byte $0E,$0E,$0E,$0E,$0E,$0E,$0E,$00 ; 0E
   .byte $0F,$0F,$0F,$0F,$0F,$0F,$0F,$00 ; 0F
   .byte $10,$10,$10,$10,$10,$10,$10,$00 ; 10
   .byte $11,$11,$11,$11,$11,$11,$11,$00 ; 11
   .byte $12,$12,$12,$12,$12,$12,$12,$00 ; 12
   .byte $13,$13,$13,$13,$13,$13,$13,$00 ; 13
   .byte $14,$14,$14,$14,$14,$14,$14,$00 ; 14
   .byte $15,$15,$15,$15,$15,$15,$15,$00 ; 15
   .byte $16,$16,$16,$16,$16,$16,$16,$00 ; 16
   .byte $17,$17,$17,$17,$17,$17,$17,$00 ; 17
   .byte $18,$18,$18,$18,$18,$18,$18,$00 ; 18
   .byte $19,$19,$19,$19,$19,$19,$19,$00 ; 19
   .byte $1A,$1A,$1A,$1A,$1A,$1A,$1A,$00 ; 1A
   .byte $1B,$1B,$1B,$1B,$1B,$1B,$1B,$00 ; 1B
   .byte $1C,$1C,$1C,$1C,$1C,$1C,$1C,$00 ; 1C
   .byte $1D,$1D,$1D,$1D,$1D,$1D,$1D,$00 ; 1D
   .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$00 ; 1E
   .byte $1F,$1F,$1F,$1F,$1F,$1F,$1F,$00 ; 1F
 ; </nonsense>
   .byte $00,$00,$00,$00,$00,$00,$00,$00 ; ' '
   .byte $20,$20,$20,$00,$20,$20,$00,$00 ; !
   .byte $50,$50,$50,$00,$00,$00,$00,$00 ; "
   .byte $50,$50,$F8,$50,$F8,$50,$50,$00 ; #
   .byte $20,$78,$A0,$70,$28,$F0,$20,$00 ; $
   .byte $C0,$C8,$10,$20,$40,$98,$18,$00 ; %
   .byte $40,$A0,$A0,$40,$A8,$90,$68,$00 ; &
   .byte $20,$20,$40,$00,$00,$00,$00,$00 ; '
   .byte $20,$40,$80,$80,$80,$40,$20,$00 ; (
   .byte $20,$10,$08,$08,$08,$10,$20,$00 ; )
   .byte $20,$A8,$70,$20,$70,$A8,$20,$00 ; *
   .byte $00,$20,$20,$F8,$20,$20,$00,$00 ; +
   .byte $00,$00,$00,$00,$20,$20,$40,$00 ; ,
   .byte $00,$00,$00,$F8,$00,$00,$00,$00 ; -
   .byte $00,$00,$00,$00,$20,$20,$00,$00 ; .
   .byte $00,$08,$10,$20,$40,$80,$00,$00 ; /
   .byte $70,$88,$98,$A8,$C8,$88,$70,$00 ; 0
   .byte $20,$60,$20,$20,$20,$20,$70,$00 ; 1 
   .byte $70,$88,$08,$30,$40,$80,$F8,$00 ; 2 
   .byte $F8,$08,$10,$30,$08,$88,$70,$00 ; 3
   .byte $10,$30,$50,$90,$F8,$10,$10,$00 ; 4
   .byte $F8,$80,$F0,$08,$08,$88,$70,$00 ; 5
   .byte $38,$40,$80,$F0,$88,$88,$70,$00 ; 6
   .byte $F8,$08,$10,$20,$40,$40,$40,$00 ; 7
   .byte $70,$88,$88,$70,$88,$88,$70,$00 ; 8
   .byte $70,$88,$88,$78,$08,$10,$E0,$00 ; 9
   .byte $00,$00,$20,$00,$20,$00,$00,$00 ; :
   .byte $00,$00,$20,$00,$20,$20,$40,$00 ; ;
   .byte $10,$20,$40,$80,$40,$20,$10,$00 ; <
   .byte $00,$00,$F8,$00,$F8,$00,$00,$00 ; =
   .byte $40,$20,$10,$08,$10,$20,$40,$00 ; >
   .byte $70,$88,$10,$20,$20,$00,$20,$00 ; ?
   .byte $70,$88,$A8,$B8,$B0,$80,$78,$00 ; @
   .byte $20,$50,$88,$88,$F8,$88,$88,$00 ; A 04
   .byte $F0,$88,$88,$F0,$88,$88,$F0,$00 ; B
   .byte $70,$88,$80,$80,$80,$88,$70,$00 ; C
   .byte $F0,$88,$88,$88,$88,$88,$F0,$00 ; D
   .byte $F8,$80,$80,$F0,$80,$80,$F8,$00 ; E 05
   .byte $F8,$80,$80,$F0,$80,$80,$80,$00 ; F
   .byte $78,$80,$80,$80,$98,$88,$78,$00 ; G
   .byte $88,$88,$88,$F8,$88,$88,$88,$00 ; H
   .byte $70,$20,$20,$20,$20,$20,$70,$00 ; I
   .byte $08,$08,$08,$08,$08,$88,$70,$00 ; J
   .byte $88,$90,$A0,$C0,$A0,$90,$88,$00 ; K
   .byte $80,$80,$80,$80,$80,$80,$F8,$00 ; L 06
   .byte $88,$D8,$A8,$A8,$88,$88,$88,$00 ; M
   .byte $88,$88,$C8,$A8,$98,$88,$88,$00 ; N
   .byte $70,$88,$88,$88,$88,$88,$70,$00 ; O
   .byte $F0,$88,$88,$F0,$80,$80,$80,$00 ; P 07
   .byte $70,$88,$88,$88,$A8,$90,$68,$00 ; Q
   .byte $F0,$88,$88,$F0,$A0,$90,$88,$00 ; R 08
   .byte $70,$88,$80,$70,$08,$88,$70,$00 ; S
   .byte $F8,$20,$20,$20,$20,$20,$20,$00 ; T
   .byte $88,$88,$88,$88,$88,$88,$70,$00 ; U
   .byte $88,$88,$88,$88,$50,$50,$20,$00 ; V
   .byte $88,$88,$88,$A8,$A8,$D8,$88,$00 ; W
   .byte $88,$88,$50,$20,$50,$88,$88,$00 ; X
   .byte $88,$88,$50,$20,$20,$20,$20,$00 ; Y 09
   .byte $F8,$08,$10,$20,$40,$80,$F8,$00 ; Z
   .byte $F8,$C0,$C0,$C0,$C0,$C0,$F8,$00 ; [
   .byte $00,$80,$40,$20,$10,$08,$00,$00 ; \
   .byte $F8,$18,$18,$18,$18,$18,$F8,$00 ; ]
   .byte $00,$00,$20,$50,$88,$00,$00,$00 ; ^
   .byte $00,$00,$00,$00,$00,$00,$F8,$00 ; _
   .byte $40,$20,$10,$00,$00,$00,$00,$00 ; `
   .byte $00,$00,$70,$88,$88,$98,$68,$00 ; a
   .byte $80,$80,$F0,$88,$88,$88,$F0,$00 ; b
   .byte $00,$00,$78,$80,$80,$80,$78,$00 ; c
   .byte $08,$08,$78,$88,$88,$88,$78,$00 ; d
   .byte $00,$00,$70,$88,$F8,$80,$78,$00 ; e
   .byte $30,$40,$E0,$40,$40,$40,$40,$00 ; f
   .byte $00,$00,$70,$88,$F8,$08,$F0,$00 ; g
   .byte $80,$80,$F0,$88,$88,$88,$88,$00 ; h
   .byte $00,$40,$00,$40,$40,$40,$40,$00 ; i
   .byte $00,$20,$00,$20,$20,$A0,$60,$00 ; j
   .byte $00,$80,$80,$A0,$C0,$A0,$90,$00 ; k
   .byte $C0,$40,$40,$40,$40,$40,$60,$00 ; l
   .byte $00,$00,$D8,$A8,$A8,$A8,$A8,$00 ; m
   .byte $00,$00,$F0,$88,$88,$88,$88,$00 ; n
   .byte $00,$00,$70,$88,$88,$88,$70,$00 ; o
   .byte $00,$00,$70,$88,$F0,$80,$80,$00 ; p
   .byte $00,$00,$F0,$88,$78,$08,$08,$00 ; q
   .byte $00,$00,$70,$88,$80,$80,$80,$00 ; r
   .byte $00,$00,$78,$80,$70,$08,$F0,$00 ; s
   .byte $40,$40,$F0,$40,$40,$40,$30,$00 ; t
   .byte $00,$00,$88,$88,$88,$88,$78,$00 ; u
   .byte $00,$00,$88,$88,$90,$A0,$40,$00 ; v
   .byte $00,$00,$88,$88,$88,$A8,$D8,$00 ; w
   .byte $00,$00,$88,$50,$20,$50,$88,$00 ; x
   .byte $00,$00,$88,$88,$78,$08,$F0,$00 ; y
   .byte $00,$00,$F8,$10,$20,$40,$F8,$00 ; z
   .byte $38,$40,$20,$C0,$20,$40,$38,$00 ; {
   .byte $40,$40,$40,$00,$40,$40,$40,$00 ; |
   .byte $E0,$10,$20,$18,$20,$10,$E0,$00 ; }
   .byte $00,$00,$24,$00,$00,$42,$3C,$00 ; ~
   .byte $A8,$50,$A8,$50,$A8,$50,$A8,$00 ; checkerboard
   ; ---- cifre grandi 16x16 (4 tile ciascuna: alto-sx, alto-dx, basso-sx, basso-dx) ----
   .byte $07,$07,$18,$18,$18,$18,$19,$19   ; big 0 alto-sx
   .byte $E0,$E0,$18,$18,$78,$78,$98,$98   ; big 0 alto-dx
   .byte $1E,$1E,$18,$18,$07,$07,$00,$00   ; big 0 basso-sx
   .byte $18,$18,$18,$18,$E0,$E0,$00,$00   ; big 0 basso-dx
   .byte $01,$01,$07,$07,$01,$01,$01,$01   ; big 1 alto-sx
   .byte $80,$80,$80,$80,$80,$80,$80,$80   ; big 1 alto-dx
   .byte $01,$01,$01,$01,$07,$07,$00,$00   ; big 1 basso-sx
   .byte $80,$80,$80,$80,$E0,$E0,$00,$00   ; big 1 basso-dx
   .byte $07,$07,$18,$18,$00,$00,$01,$01   ; big 2 alto-sx
   .byte $E0,$E0,$18,$18,$18,$18,$E0,$E0   ; big 2 alto-dx
   .byte $06,$06,$18,$18,$1F,$1F,$00,$00   ; big 2 basso-sx
   .byte $00,$00,$00,$00,$F8,$F8,$00,$00   ; big 2 basso-dx
   .byte $1F,$1F,$00,$00,$00,$00,$01,$01   ; big 3 alto-sx
   .byte $F8,$F8,$18,$18,$60,$60,$E0,$E0   ; big 3 alto-dx
   .byte $00,$00,$18,$18,$07,$07,$00,$00   ; big 3 basso-sx
   .byte $18,$18,$18,$18,$E0,$E0,$00,$00   ; big 3 basso-dx
   .byte $00,$00,$01,$01,$06,$06,$18,$18   ; big 4 alto-sx
   .byte $60,$60,$E0,$E0,$60,$60,$60,$60   ; big 4 alto-dx
   .byte $1F,$1F,$00,$00,$00,$00,$00,$00   ; big 4 basso-sx
   .byte $F8,$F8,$60,$60,$60,$60,$00,$00   ; big 4 basso-dx
   .byte $1F,$1F,$18,$18,$1F,$1F,$00,$00   ; big 5 alto-sx
   .byte $F8,$F8,$00,$00,$E0,$E0,$18,$18   ; big 5 alto-dx
   .byte $00,$00,$18,$18,$07,$07,$00,$00   ; big 5 basso-sx
   .byte $18,$18,$18,$18,$E0,$E0,$00,$00   ; big 5 basso-dx
   .byte $01,$01,$06,$06,$18,$18,$1F,$1F   ; big 6 alto-sx
   .byte $F8,$F8,$00,$00,$00,$00,$E0,$E0   ; big 6 alto-dx
   .byte $18,$18,$18,$18,$07,$07,$00,$00   ; big 6 basso-sx
   .byte $18,$18,$18,$18,$E0,$E0,$00,$00   ; big 6 basso-dx
   .byte $1F,$1F,$00,$00,$00,$00,$01,$01   ; big 7 alto-sx
   .byte $F8,$F8,$18,$18,$60,$60,$80,$80   ; big 7 alto-dx
   .byte $06,$06,$06,$06,$06,$06,$00,$00   ; big 7 basso-sx
   .byte $00,$00,$00,$00,$00,$00,$00,$00   ; big 7 basso-dx
   .byte $07,$07,$18,$18,$18,$18,$07,$07   ; big 8 alto-sx
   .byte $E0,$E0,$18,$18,$18,$18,$E0,$E0   ; big 8 alto-dx
   .byte $18,$18,$18,$18,$07,$07,$00,$00   ; big 8 basso-sx
   .byte $18,$18,$18,$18,$E0,$E0,$00,$00   ; big 8 basso-dx
   .byte $07,$07,$18,$18,$18,$18,$07,$07   ; big 9 alto-sx
   .byte $E0,$E0,$18,$18,$18,$18,$F8,$F8   ; big 9 alto-dx
   .byte $00,$00,$00,$00,$1F,$1F,$00,$00   ; big 9 basso-sx
   .byte $18,$18,$60,$60,$80,$80,$00,$00   ; big 9 basso-dx
   ; ---- lettere grandi per schermate START / FINE ----
   .byte $1F,$1F,$01,$01,$01,$01,$01,$01   ; big T alto-sx
   .byte $F8,$F8,$80,$80,$80,$80,$80,$80   ; big T alto-dx
   .byte $01,$01,$01,$01,$01,$01,$00,$00   ; big T basso-sx
   .byte $80,$80,$80,$80,$80,$80,$00,$00   ; big T basso-dx
   .byte $01,$01,$06,$06,$18,$18,$18,$18   ; big A alto-sx
   .byte $80,$80,$60,$60,$18,$18,$18,$18   ; big A alto-dx
   .byte $1F,$1F,$18,$18,$18,$18,$00,$00   ; big A basso-sx
   .byte $F8,$F8,$18,$18,$18,$18,$00,$00   ; big A basso-dx
   .byte $18,$18,$18,$18,$1E,$1E,$19,$19   ; big N alto-sx
   .byte $18,$18,$18,$18,$18,$18,$98,$98   ; big N alto-dx
   .byte $18,$18,$18,$18,$18,$18,$00,$00   ; big N basso-sx
   .byte $78,$78,$18,$18,$18,$18,$00,$00   ; big N basso-dx
   .byte $18,$18,$18,$18,$18,$18,$1F,$1F   ; big H alto-sx
   .byte $18,$18,$18,$18,$18,$18,$F8,$F8   ; big H alto-dx
   .byte $18,$18,$18,$18,$18,$18,$00,$00   ; big H basso-sx
   .byte $18,$18,$18,$18,$18,$18,$00,$00   ; big H basso-dx
   .byte $1F,$1F,$18,$18,$18,$18,$1F,$1F   ; big E alto-sx
   .byte $F8,$F8,$00,$00,$00,$00,$E0,$E0   ; big E alto-dx
   .byte $18,$18,$18,$18,$1F,$1F,$00,$00   ; big E basso-sx
   .byte $00,$00,$00,$00,$F8,$F8,$00,$00   ; big E basso-dx
   .byte $1F,$1F,$18,$18,$18,$18,$1F,$1F   ; big F alto-sx
   .byte $F8,$F8,$00,$00,$00,$00,$E0,$E0   ; big F alto-dx
   .byte $18,$18,$18,$18,$18,$18,$00,$00   ; big F basso-sx
   .byte $00,$00,$00,$00,$00,$00,$00,$00   ; big F basso-dx
   .byte $07,$07,$01,$01,$01,$01,$01,$01   ; big I alto-sx
   .byte $E0,$E0,$80,$80,$80,$80,$80,$80   ; big I alto-dx
   .byte $01,$01,$01,$01,$07,$07,$00,$00   ; big I basso-sx
   .byte $80,$80,$80,$80,$E0,$E0,$00,$00   ; big I basso-dx
   .byte $18,$18,$18,$18,$18,$18,$18,$18   ; big L alto-sx
   .byte $00,$00,$00,$00,$00,$00,$00,$00   ; big L alto-dx
   .byte $18,$18,$18,$18,$1F,$1F,$00,$00   ; big L basso-sx
   .byte $00,$00,$00,$00,$F8,$F8,$00,$00   ; big L basso-dx
   .byte $07,$07,$18,$18,$18,$18,$18,$18   ; big C alto-sx
   .byte $E0,$E0,$18,$18,$00,$00,$00,$00   ; big C alto-dx
   .byte $18,$18,$18,$18,$07,$07,$00,$00   ; big C basso-sx
   .byte $00,$00,$18,$18,$E0,$E0,$00,$00   ; big C basso-dx
   .byte $07,$07,$18,$18,$18,$18,$18,$18   ; big O alto-sx
   .byte $E0,$E0,$18,$18,$18,$18,$18,$18   ; big O alto-dx
   .byte $18,$18,$18,$18,$07,$07,$00,$00   ; big O basso-sx
   .byte $18,$18,$18,$18,$E0,$E0,$00,$00   ; big O basso-dx
   .byte $1F,$1F,$18,$18,$18,$18,$18,$18   ; big D alto-sx
   .byte $E0,$E0,$18,$18,$18,$18,$18,$18   ; big D alto-dx
   .byte $18,$18,$18,$18,$1F,$1F,$00,$00   ; big D basso-sx
   .byte $18,$18,$18,$18,$E0,$E0,$00,$00   ; big D basso-dx
   .byte $18,$18,$18,$18,$18,$18,$18,$18   ; big U alto-sx
   .byte $18,$18,$18,$18,$18,$18,$18,$18   ; big U alto-dx
   .byte $18,$18,$18,$18,$07,$07,$00,$00   ; big U basso-sx
   .byte $18,$18,$18,$18,$E0,$E0,$00,$00   ; big U basso-dx
   .byte $18,$18,$18,$18,$18,$18,$19,$19   ; big W alto-sx
   .byte $18,$18,$18,$18,$18,$18,$98,$98   ; big W alto-dx
   .byte $19,$19,$1E,$1E,$18,$18,$00,$00   ; big W basso-sx
   .byte $98,$98,$78,$78,$18,$18,$00,$00   ; big W basso-dx
   .byte $1F,$1F,$18,$18,$18,$18,$1F,$1F   ; big P alto-sx
   .byte $E0,$E0,$18,$18,$18,$18,$E0,$E0   ; big P alto-dx
   .byte $18,$18,$18,$18,$18,$18,$00,$00   ; big P basso-sx
   .byte $00,$00,$00,$00,$00,$00,$00,$00   ; big P basso-dx
   .byte $18,$18,$18,$18,$06,$06,$01,$01   ; big Y alto-sx
   .byte $18,$18,$18,$18,$60,$60,$80,$80   ; big Y alto-dx
   .byte $01,$01,$01,$01,$01,$01,$00,$00   ; big Y basso-sx
   .byte $80,$80,$80,$80,$80,$80,$00,$00   ; big Y basso-dx
   .byte $1F,$1F,$18,$18,$18,$18,$1F,$1F   ; big R alto-sx
   .byte $E0,$E0,$18,$18,$18,$18,$E0,$E0   ; big R alto-dx
   .byte $19,$19,$18,$18,$18,$18,$00,$00   ; big R basso-sx
   .byte $80,$80,$60,$60,$18,$18,$00,$00   ; big R basso-dx
   .byte $07,$07,$18,$18,$18,$18,$07,$07   ; big S alto-sx
   .byte $E0,$E0,$18,$18,$00,$00,$E0,$E0   ; big S alto-dx
   .byte $00,$00,$18,$18,$07,$07,$00,$00   ; big S basso-sx
   .byte $18,$18,$18,$18,$E0,$E0,$00,$00   ; big S basso-dx
   .byte $01,$01,$01,$01,$01,$01,$00,$00   ; big ! alto-sx
   .byte $80,$80,$80,$80,$80,$80,$00,$00   ; big ! alto-dx
   .byte $01,$01,$01,$01,$00,$00,$00,$00   ; big ! basso-sx
   .byte $80,$80,$80,$80,$00,$00,$00,$00   ; big ! basso-dx
VDP_END_PATTERNS:


; ---------------------------------------------------------------
; NAME TABLE del campo di gioco: tile 01 = verde (percorribile)
; riga 0 = scritte PLAYER 1 / PLAYER 2; il punteggio grande si disegna sotto (riga 2)
; MODIFICHE rispetto a PATTERN_003: riga 4 e 19 colonne 14-19 (ponti centrali a 2 caselle),
; righe 9 e 14 colonne 6 e 25 (angoli laterali: blocco 2x2 al posto dello scalino),
; righe 7 e 16 colonne 13 e 18 (bordo del vuoto centrale: blocco 2x2 al posto dello scalino)
; ---------------------------------------------------------------
VDP_NAME:
   .byte $50, $4C, $41, $59, $45, $52, $00, $31
   .byte $00, $00, $00, $00, $00, $00, $00, $00
   .byte $00, $00, $00, $00, $00, $00, $00, $00
   .byte $50, $4C, $41, $59, $45, $52, $00, $32

   .byte $00, $00, $00, $00, $00, $00, $00, $00
   .byte $01, $01, $01, $01, $01, $01, $00, $00
   .byte $00, $00, $01, $01, $01, $01, $01, $01
   .byte $00, $00, $00, $00, $00, $00, $00, $00

   .byte $00, $00, $00, $00, $00, $00, $00, $00
   .byte $01, $01, $01, $01, $01, $01, $00, $00
   .byte $00, $00, $01, $01, $01, $01, $01, $01
   .byte $00, $00, $00, $00, $00, $00, $00, $00

   .byte $00, $00, $00, $00, $00, $00, $00, $00
   .byte $01, $01, $01, $01, $01, $01, $00, $00
   .byte $00, $00, $01, $01, $01, $01, $01, $01
   .byte $00, $00, $00, $00, $00, $00, $00, $00

   .byte $00, $00, $00, $00, $00, $00, $00, $00
   .byte $01, $01, $01, $01, $01, $01, $01, $01
   .byte $01, $01, $01, $01, $01, $01, $01, $01
   .byte $00, $00, $00, $00, $00, $00, $00, $00

   .byte $00, $00, $00, $00, $00, $00, $01, $01
   .byte $01, $01, $00, $00, $01, $01, $01, $01
   .byte $01, $01, $01, $01, $00, $00, $01, $01
   .byte $01, $01, $00, $00, $00, $00, $00, $00

   .byte $00, $01, $01, $01, $01, $01, $01, $01
   .byte $01, $01, $01, $01, $01, $01, $00, $00
   .byte $00, $00, $01, $01, $01, $01, $01, $01
   .byte $01, $01, $01, $01, $01, $01, $01, $00

   .byte $00, $01, $01, $01, $01, $01, $01, $01
   .byte $01, $01, $01, $01, $01, $01, $00, $00
   .byte $00, $00, $01, $01, $01, $01, $01, $01
   .byte $01, $01, $01, $01, $01, $01, $01, $00

   .byte $00, $01, $01, $00, $00, $00, $00, $00
   .byte $00, $01, $01, $01, $00, $00, $00, $00
   .byte $00, $00, $00, $00, $01, $01, $01, $00
   .byte $00, $00, $00, $00, $00, $01, $01, $00

   .byte $00, $01, $01, $01, $01, $01, $01, $00
   .byte $00, $01, $01, $01, $00, $00, $00, $00
   .byte $00, $00, $00, $00, $01, $01, $01, $00
   .byte $00, $01, $01, $01, $01, $01, $01, $00

   .byte $00, $01, $01, $01, $01, $01, $01, $00
   .byte $00, $01, $01, $01, $01, $01, $01, $01
   .byte $01, $01, $01, $01, $01, $01, $01, $00
   .byte $00, $01, $01, $01, $01, $01, $01, $00

   .byte $00, $00, $00, $00, $00, $01, $01, $01
   .byte $01, $01, $01, $01, $01, $01, $01, $01
   .byte $01, $01, $01, $01, $01, $01, $01, $01
   .byte $01, $01, $01, $00, $00, $00, $00, $00

   .byte $00, $00, $00, $00, $00, $01, $01, $01
   .byte $01, $01, $01, $01, $01, $01, $01, $01
   .byte $01, $01, $01, $01, $01, $01, $01, $01
   .byte $01, $01, $01, $00, $00, $00, $00, $00

   .byte $00, $01, $01, $01, $01, $01, $01, $00
   .byte $00, $01, $01, $01, $01, $01, $01, $01
   .byte $01, $01, $01, $01, $01, $01, $01, $00
   .byte $00, $01, $01, $01, $01, $01, $01, $00

   .byte $00, $01, $01, $01, $01, $01, $01, $00
   .byte $00, $01, $01, $01, $00, $00, $00, $00
   .byte $00, $00, $00, $00, $01, $01, $01, $00
   .byte $00, $01, $01, $01, $01, $01, $01, $00

   .byte $00, $01, $01, $00, $00, $00, $00, $00
   .byte $00, $01, $01, $01, $00, $00, $00, $00
   .byte $00, $00, $00, $00, $01, $01, $01, $00
   .byte $00, $00, $00, $00, $00, $01, $01, $00

   .byte $00, $01, $01, $01, $01, $01, $01, $01
   .byte $01, $01, $01, $01, $01, $01, $00, $00
   .byte $00, $00, $01, $01, $01, $01, $01, $01
   .byte $01, $01, $01, $01, $01, $01, $01, $00

   .byte $00, $01, $01, $01, $01, $01, $01, $01
   .byte $01, $01, $01, $01, $01, $01, $00, $00
   .byte $00, $00, $01, $01, $01, $01, $01, $01
   .byte $01, $01, $01, $01, $01, $01, $01, $00

   .byte $00, $00, $00, $00, $00, $00, $01, $01
   .byte $01, $01, $00, $00, $01, $01, $01, $01
   .byte $01, $01, $01, $01, $00, $00, $01, $01
   .byte $01, $01, $00, $00, $00, $00, $00, $00

   .byte $00, $00, $00, $00, $00, $00, $00, $00
   .byte $01, $01, $01, $01, $01, $01, $01, $01
   .byte $01, $01, $01, $01, $01, $01, $01, $01
   .byte $00, $00, $00, $00, $00, $00, $00, $00

   .byte $00, $00, $00, $00, $00, $00, $00, $00
   .byte $01, $01, $01, $01, $01, $01, $00, $00
   .byte $00, $00, $01, $01, $01, $01, $01, $01
   .byte $00, $00, $00, $00, $00, $00, $00, $00

   .byte $00, $00, $00, $00, $00, $00, $00, $00
   .byte $01, $01, $01, $01, $01, $01, $00, $00
   .byte $00, $00, $01, $01, $01, $01, $01, $01
   .byte $00, $00, $00, $00, $00, $00, $00, $00

   .byte $00, $00, $00, $00, $00, $00, $00, $00
   .byte $01, $01, $01, $01, $01, $01, $00, $00
   .byte $00, $00, $01, $01, $01, $01, $01, $01
   .byte $00, $00, $00, $00, $00, $00, $00, $00

   .byte $00, $00, $00, $00, $00, $00, $00, $00
   .byte $00, $00, $00, $00, $00, $00, $00, $00
   .byte $00, $00, $00, $00, $00, $00, $00, $00
   .byte $00, $00, $00, $00, $00, $00, $00, $00

VDP_END_NAME:


; ---------------------------------------------------------------
; schermate: record  riga, colonna, lunghezza, tile...   ($FF = fine)
; ---------------------------------------------------------------
TITLE_REC:
  .byte 0, 0, 32, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01   ; fascia verde riga 0
  .byte 1, 0, 32, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01   ; fascia verde riga 1
  .byte 22, 0, 32, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01   ; fascia verde riga 22
  .byte 23, 0, 32, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01   ; fascia verde riga 23
  .byte 3, 7, 18, $A8, $A9, $B4, $B5, $B8, $B9, $00, $00, $BC, $BD, $C0, $C1, $B0, $B1, $AC, $AD, $C4, $C5   ; THE FINAL
  .byte 4, 7, 18, $AA, $AB, $B6, $B7, $BA, $BB, $00, $00, $BE, $BF, $C2, $C3, $B2, $B3, $AE, $AF, $C6, $C7   ; THE FINAL
  .byte 6, 7, 18, $C8, $C9, $CC, $CD, $D4, $D5, $B0, $B1, $A8, $A9, $D0, $D1, $CC, $CD, $D8, $D9, $B0, $B1   ; COUNTDOWN
  .byte 7, 7, 18, $CA, $CB, $CE, $CF, $D6, $D7, $B2, $B3, $AA, $AB, $D2, $D3, $CE, $CF, $DA, $DB, $B2, $B3   ; COUNTDOWN
  .byte 9, 5, 21, $54, $20, $41, $20, $4E, $20, $4B, $20, $20, $20, $42, $20, $41, $20, $54, $20, $54, $20, $4C, $20, $45   ; T A N K   B A T T L E
  .byte 14, 7, 17, $4C, $45, $46, $54, $2F, $52, $49, $47, $48, $54, $20, $3D, $20, $54, $55, $52, $4E   ; LEFT/RIGHT = TURN
  .byte 16, 8, 15, $42, $55, $54, $54, $4F, $4E, $20, $31, $20, $3D, $20, $4D, $4F, $56, $45   ; BUTTON 1 = MOVE
  .byte 18, 8, 15, $42, $55, $54, $54, $4F, $4E, $20, $32, $20, $3D, $20, $46, $49, $52, $45   ; BUTTON 2 = FIRE
  .byte 11, 5, 22, $46, $49, $52, $53, $54, $20, $54, $4F, $20, WIN_SCORE+$30, $20, $50, $4F, $49, $4E, $54, $53, $20, $57, $49, $4E, $53   ; FIRST TO <WIN_SCORE> POINTS WINS
  .byte $FF

TITLE_PRESS:
  .byte 20, 6, 19, $50, $52, $45, $53, $53, $20, $46, $49, $52, $45, $20, $54, $4F, $20, $53, $54, $41, $52, $54   ; PRESS FIRE TO START
  .byte $FF

END_REC:
  .byte 0, 0, 32, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01   ; fascia verde riga 0
  .byte 1, 0, 32, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01   ; fascia verde riga 1
  .byte 22, 0, 32, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01   ; fascia verde riga 22
  .byte 23, 0, 32, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01   ; fascia verde riga 23
  .byte 7, 11, 10, $D8, $D9, $C0, $C1, $B0, $B1, $E8, $E9, $EC, $ED   ; WINS!
  .byte 8, 11, 10, $DA, $DB, $C2, $C3, $B2, $B3, $EA, $EB, $EE, $EF   ; WINS!
  .byte 11, 10, 11, $46, $49, $4E, $41, $4C, $20, $53, $43, $4F, $52, $45   ; FINAL SCORE
  .byte 13, 9, 2, $50, $31   ; P1
  .byte 13, 21, 2, $50, $32   ; P2
  .byte 15, 15, 2, $2D, $2D   ; --
  .byte 20, 5, 22, $50, $52, $45, $53, $53, $20, $46, $49, $52, $45, $20, $54, $4F, $20, $43, $4F, $4E, $54, $49, $4E, $55, $45   ; PRESS FIRE TO CONTINUE
  .byte $FF

BANNER_1:
  .byte 3, 8, 16, $DC, $DD, $C4, $C5, $AC, $AD, $E0, $E1, $B8, $B9, $E4, $E5, $00, $00, $84, $85   ; PLAYER 1
  .byte 4, 8, 16, $DE, $DF, $C6, $C7, $AE, $AF, $E2, $E3, $BA, $BB, $E6, $E7, $00, $00, $86, $87   ; PLAYER 1
  .byte $FF

BANNER_2:
  .byte 3, 8, 16, $DC, $DD, $C4, $C5, $AC, $AD, $E0, $E1, $B8, $B9, $E4, $E5, $00, $00, $88, $89   ; PLAYER 2
  .byte 4, 8, 16, $DE, $DF, $C6, $C7, $AE, $AF, $E2, $E3, $BA, $BB, $E6, $E7, $00, $00, $8A, $8B   ; PLAYER 2
  .byte $FF


VDP_SPRITE:
   .byte   $00,$01,$01,$01,$01,$07,$0C,$0B  ; TANK UP
   .byte   $0B,$0B,$0B,$0B,$0C,$07,$00,$00  ; Sprite Name 00
   .byte   $00,$80,$80,$80,$80,$E0,$30,$D0
   .byte   $D0,$D0,$D0,$D0,$30,$E0,$00,$00
   
   .byte   $00,$00,$00,$00,$03,$04,$09,$13  ; TANK UP-RG
   .byte   $27,$2F,$27,$12,$08,$07,$00,$00  ; Sprite Name 01
   .byte   $00,$00,$08,$1C,$B8,$70,$10,$90
   .byte   $D0,$90,$20,$40,$80,$00,$00,$00
   
   .byte   $00,$00,$00,$00,$1F,$30,$2F,$2F  ; TANK RG
   .byte   $2F,$2F,$30,$1F,$00,$00,$00,$00  ; Sprite Name 02
   .byte   $00,$00,$00,$00,$C0,$60,$A0,$BE
   .byte   $BE,$A0,$60,$C0,$00,$00,$00,$00
   
   .byte   $00,$00,$07,$08,$12,$27,$2F,$27  ; TANK RG-DW
   .byte   $13,$09,$04,$03,$00,$00,$00,$00  ; Sprite Name 03
   .byte   $00,$00,$00,$80,$40,$20,$90,$D0
   .byte   $90,$20,$70,$B8,$1C,$08,$00,$00
   
   .byte   $00,$00,$07,$0C,$0B,$0B,$0B,$0B  ; TANK DW
   .byte   $0B,$0C,$07,$01,$01,$01,$01,$00  ; Sprite Name 04
   .byte   $00,$00,$E0,$30,$D0,$D0,$D0,$D0
   .byte   $D0,$30,$E0,$80,$80,$80,$80,$00

   .byte   $00,$00,$00,$01,$02,$04,$09,$0B  ; TANK DW-LF
   .byte   $09,$04,$0E,$1D,$38,$10,$00,$00  ; Sprite Name 05
   .byte   $00,$00,$E0,$10,$48,$E4,$F4,$E4
   .byte   $C8,$90,$20,$C0,$00,$00,$00,$00
   
   .byte   $00,$00,$00,$00,$03,$06,$05,$7D  ; TANK LF
   .byte   $7D,$05,$06,$03,$00,$00,$00,$00  ; Sprite Name 06
   .byte   $00,$00,$00,$00,$F8,$0C,$F4,$F4
   .byte   $F4,$F4,$0C,$F8,$00,$00,$00,$00
   
   .byte   $00,$00,$10,$38,$1D,$0E,$04,$09  ; TANK LF-UP
   .byte   $0B,$09,$04,$02,$01,$00,$00,$00  ; Sprite Name 07
   .byte   $00,$00,$00,$00,$C0,$20,$90,$C8
   .byte   $E4,$F4,$E4,$48,$10,$E0,$00,$00
   ; BULLET
   .byte   $00,$00,$01,$01,$01,$00,$00,$00
   .byte   $00,$00,$00,$00,$00,$00,$00,$00
   .byte   $00,$00,$80,$80,$80,$00,$00,$00
   .byte   $00,$00,$00,$00,$00,$00,$00,$00
   
   .byte   $00,$00,$00,$00,$00,$00,$00,$00
   .byte   $00,$00,$00,$00,$00,$00,$00,$00
   .byte   $00,$00,$00,$10,$38,$70,$20,$00
   .byte   $00,$00,$00,$00,$00,$00,$00,$00
   
   .byte   $00,$00,$00,$00,$00,$00,$00,$00
   .byte   $00,$00,$00,$00,$00,$00,$00,$00
   .byte   $00,$00,$00,$00,$00,$00,$00,$1C
   .byte   $1C,$00,$00,$00,$00,$00,$00,$00
   
   .byte   $00,$00,$00,$00,$00,$00,$00,$00
   .byte   $00,$00,$00,$00,$00,$00,$00,$00
   .byte   $00,$00,$00,$00,$00,$00,$00,$00
   .byte   $00,$20,$70,$38,$10,$00,$00,$00
   
   .byte   $00,$00,$00,$00,$00,$00,$00,$00
   .byte   $00,$00,$00,$01,$01,$01,$00,$00
   .byte   $00,$00,$00,$00,$00,$00,$00,$00
   .byte   $00,$00,$00,$80,$80,$80,$00,$00
   
   .byte   $00,$00,$00,$00,$00,$00,$00,$00
   .byte   $00,$04,$0E,$1C,$08,$00,$00,$00
   .byte   $00,$00,$00,$00,$00,$00,$00,$00
   .byte   $00,$00,$00,$00,$00,$00,$00,$00
   
   .byte   $00,$00,$00,$00,$00,$00,$00,$38
   .byte   $38,$00,$00,$00,$00,$00,$00,$00
   .byte   $00,$00,$00,$00,$00,$00,$00,$00
   .byte   $00,$00,$00,$00,$00,$00,$00,$00
   
   .byte   $00,$00,$00,$08,$1C,$0E,$04,$00
   .byte   $00,$00,$00,$00,$00,$00,$00,$00
   .byte   $00,$00,$00,$00,$00,$00,$00,$00
   .byte   $00,$00,$00,$00,$00,$00,$00,$00

   ; ESPLOSIONE frame 0  (sprite name 64)
   .byte $00,$01,$01,$19,$19,$07,$07,$7F
   .byte $7F,$07,$07,$19,$19,$01,$01,$00
   .byte $00,$80,$80,$98,$98,$E0,$E0,$FE
   .byte $FE,$E0,$E0,$98,$98,$80,$80,$00

   ; ESPLOSIONE frame 1  (sprite name 68)
   .byte $01,$01,$35,$3C,$08,$04,$31,$E3
   .byte $E3,$01,$34,$18,$32,$33,$01,$01
   .byte $80,$80,$CC,$4C,$18,$2C,$80,$C7
   .byte $C7,$8C,$20,$10,$3C,$AC,$80,$80


VDP_END_SPRITE:

DELTA_X:
  .byte $00, $01, $01, $01, $00, $FF, $FF, $FF

DELTA_Y:
  .byte $FF, $FF, $00, $01, $01, $01, $00, $FF

VDP_COLOR:
   .byte $11,$11,$11,$11,$11,$11,$11,$11   ;00 black on black
   .byte $CC,$CC,$CC,$CC,$CC,$CC,$CC,$CC   ;01 dark green on dark green
   .byte $F1,$F1,$F1,$F1,$F1,$F1,$F1,$F1   ;da 02 in poi: white on black ("congelato")
VDP_END_COLOR:


; ===============================================================
;  SONORO  -  due AY-3-8910 (sinistro = tank 1, destro = tank 2)
;  Tutto il suono e' suonato da SND_TICK, chiamata dall'NMI a 60 Hz.
;  Il main loop non scrive mai sugli AY: lascia solo comandi e flag
;  (SND_CMD, SFX_EXPL, SFX_SHOT, SND_MV), cosi' non ci sono conflitti.
;  Gli AY si scrivono dagli shadow SH_L / SH_R (registri 0-10).
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
  STA SFX_EXPL
  STA SFX_SHOT
  STA SFX_SHOT+1
  STA SND_MV
  STA SND_MV+1
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
  SBC #CMD_TITLE                ; 0 = titolo, 1 = vittoria
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
; effetti sonori di gioco (un frame). Chip 0 = tank 1, chip 1 = tank 2.
;   canale A = sparo (tono), B = rumore (scoppio / cingoli), C = motore / botto
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
  LDA SFX_EXPL
  BEQ .sf_noexp
  ; ---- esplosione (entrambi i chip)
  LSR A
  TAX                           ; passo 0..30
  LDA EXP_NV,X
  BEQ .sf_e1
  CPX #$04
  BCC .sf_e1
  LDA SND_RND                   ; crepitio: -1 a caso
  LSR A
  LDA EXP_NV,X
  SBC #$00
.sf_e1:
  STA SH_L+9,Y
  LDA EXP_NP,X
  CPY #$00
  BEQ .sf_e2
  CLC
  ADC #$03                      ; chip destro: rumore leggermente diverso
.sf_e2:
  STA SH_L+6,Y
  LDA EXP_VC,X
  STA SH_L+10,Y
  LDA EXP_TL,X
  STA SH_L+4,Y
  LDA EXP_TH,X
  STA SH_L+5,Y
  JMP .sf_next
.sf_noexp:
  LDX SND_T1
  LDA SFX_SHOT,X
  BEQ .sf_noshot
  TAX
  DEX                           ; 0..SHOT_LEN-1
  LDA SHOT_VA,X
  STA SH_L+8,Y
  LDA SHOT_TL,X
  STA SH_L,Y
  LDA SHOT_TH,X
  STA SH_L+1,Y
  LDA SHOT_NV,X
  STA SH_L+9,Y
  LDA #$05
  STA SH_L+6,Y
.sf_noshot:
  LDX SND_T1
  LDA SND_MV,X
  BEQ .sf_next
  ; ---- motore: tono grave che "borbotta" + un velo di rumore
  LDA #ENG_VOL
  STA SH_L+10,Y
  LDA SND_PH
  LSR A
  LSR A
  AND #$01
  TAX
  LDA ENG_TL,X
  STA SH_L+4,Y
  LDA ENG_TH,X
  STA SH_L+5,Y
  LDA SH_L+9,Y                  ; se c'e' gia' il rumore dello sparo, lascialo
  BNE .sf_next
  LDA #ENG_NVOL
  STA SH_L+9,Y
  LDA #30
  STA SH_L+6,Y
.sf_next:
  LDX SND_T1
  DEX
  BMI .sf_adv
  JMP .sf_chip
.sf_adv:
  LDA SFX_EXPL                  ; avanza i timer
  BEQ .sf_a1
  INC SFX_EXPL
  LDA SFX_EXPL
  CMP #(EXPL_SND_LEN+1)
  BCC .sf_a1
  LDA #$00
  STA SFX_EXPL
.sf_a1:
  LDX #$01
.sf_a2:
  LDA SFX_SHOT,X
  BEQ .sf_a3
  INC SFX_SHOT,X
  LDA SFX_SHOT,X
  CMP #(SHOT_LEN+1)
  BCC .sf_a3
  LDA #$00
  STA SFX_SHOT,X
.sf_a3:
  DEX
  BPL .sf_a2
  RTS


; ---------------------------------------------------------------
; tabelle del sonoro (generate)
; ---------------------------------------------------------------
; per traccia 0 melodia / 1 arpeggio / 2 basso (la 4a voce e' per la batteria)
V0_TAB:        .byte 13, 9, 12, 0      ; volume all'attacco della nota
FLOOR_TAB:     .byte 9, 4, 8, 0        ; volume minimo raggiunto dal decadimento
DECMASK_TAB:   .byte 7, 3, 3, 0        ; il volume cala di 1 quando (eta' AND maschera) = 0
VIB_TAB:       .byte 0, 1, 1, 0, 0, $FF, $FF, 0   ; vibrato +-1 passo (signed)
; batteria: 1 cassa, 2 rullante, 3 charleston, 4 piatto
DRUM_NP:       .byte 0, 28, 10, 2, 5
DRUM_V0:       .byte 0, 15, 14, 8, 15
DRUM_MASK:     .byte 0, 0, 0, 0, 7
; motore: due periodi alternati (circa 62 e 66 Hz)
ENG_TL:        .byte <1010, <940
ENG_TH:        .byte >1010, >940

SONGP_LO:      .byte <TITLE_LEAD,<TITLE_HARM,<TITLE_BASS,<TITLE_DRUM,<WIN_LEAD,<WIN_HARM,<WIN_BASS,<WIN_DRUM
SONGP_HI:      .byte >TITLE_LEAD,>TITLE_HARM,>TITLE_BASS,>TITLE_DRUM,>WIN_LEAD,>WIN_HARM,>WIN_BASS,>WIN_DRUM

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

; esplosione: 31 passi da 2 frame (rumore B + colpo grave C)
EXP_NV:
  .byte $0F,$0F,$0E,$0D,$0C,$0C,$0B,$0A,$0A,$09,$09,$08,$08,$07,$06,$06
  .byte $05,$05,$04,$04,$03,$03,$03,$02,$02,$01,$01,$01,$00,$00,$00
EXP_NP:
  .byte $03,$05,$07,$08,$09,$0A,$0B,$0C,$0D,$0E,$0F,$0F,$10,$11,$12,$12
  .byte $13,$14,$14,$15,$16,$16,$17,$18,$18,$19,$1A,$1A,$1B,$1B,$1C
EXP_VC:
  .byte $0E,$0D,$0D,$0C,$0C,$0B,$0A,$0A,$09,$09,$08,$08,$07,$06,$06,$05
  .byte $05,$04,$04,$03,$02,$02,$01,$01,$00,$00,$00,$00,$00,$00,$00
EXP_TL:
  .byte $C8,$D6,$E5,$F5,$06,$18,$2B,$40,$56,$6E,$87,$A3,$C0,$DF,$00,$24
  .byte $4A,$72,$9E,$CD,$FE,$34,$6C,$A9,$EA,$30,$7B,$CA,$1F,$7B,$DC
EXP_TH:
  .byte $00,$00,$00,$00,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$02,$02
  .byte $02,$02,$02,$02,$02,$03,$03,$03,$03,$04,$04,$04,$05,$05,$05
; sparo: 12 frame (tono che scende + scoppio di rumore)
SHOT_VA:
  .byte $0D,$0C,$0A,$09,$08,$07,$06,$05,$03,$02,$02,$01
SHOT_TL:
  .byte $46,$52,$60,$71,$84,$9A,$B5,$D4,$F8,$23,$55,$8F
SHOT_TH:
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$01,$01
SHOT_NV:
  .byte $0B,$09,$06,$03,$00,$00,$00,$00,$00,$00,$00,$00

; canzone del titolo (nota, durata in frame; 0 = pausa; $FF = fine)
TITLE_LEAD:
  .byte 43,15, 41,15, 43,30, 36,60, 45,15, 43,15, 45,15, 43,15
  .byte 41,60, 45,15, 43,15, 45,30, 36,60, 41,15, 40,15, 41,15
  .byte 40,15, 38,15, 41,45, 43,15, 41,15, 43,30, 36,60, 45,15
  .byte 43,15, 45,15, 43,15, 41,60, 45,15, 43,15, 45,30, 36,60
  .byte 41,15, 40,15, 41,15, 40,15, 38,15, 41,45, 43,15, 41,15
  .byte 43,30, 36,60, 36,120
  .byte $FF
TITLE_HARM:
  .byte 27,15, 31,15, 36,15, 31,15, 27,15, 31,15, 36,15, 31,15
  .byte 29,15, 33,15, 36,15, 33,15, 29,15, 33,15, 36,15, 33,15
  .byte 29,15, 33,15, 36,15, 33,15, 29,15, 33,15, 36,15, 33,15
  .byte 29,15, 33,15, 38,15, 33,15, 29,15, 33,15, 38,15, 33,15
  .byte 27,15, 31,15, 36,15, 31,15, 27,15, 31,15, 36,15, 31,15
  .byte 29,15, 33,15, 36,15, 33,15, 29,15, 33,15, 36,15, 33,15
  .byte 29,15, 33,15, 36,15, 33,15, 29,15, 33,15, 36,15, 33,15
  .byte 29,15, 33,15, 38,15, 33,15, 29,15, 33,15, 38,15, 33,15
  .byte 27,15, 31,15, 36,15, 31,15, 27,15, 31,15, 36,15, 31,15
  .byte 31,120
  .byte $FF
TITLE_BASS:
  .byte 12,15, 12,15, 24,15, 12,15, 12,15, 12,15, 24,15, 12,15
  .byte 5,15, 5,15, 17,15, 5,15, 5,15, 5,15, 17,15, 5,15
  .byte 5,15, 5,15, 17,15, 5,15, 5,15, 5,15, 17,15, 5,15
  .byte 14,15, 14,15, 26,15, 14,15, 14,15, 14,15, 26,15, 14,15
  .byte 12,15, 12,15, 24,15, 12,15, 12,15, 12,15, 24,15, 12,15
  .byte 5,15, 5,15, 17,15, 5,15, 5,15, 5,15, 17,15, 5,15
  .byte 5,15, 5,15, 17,15, 5,15, 5,15, 5,15, 17,15, 5,15
  .byte 14,15, 14,15, 26,15, 14,15, 14,15, 14,15, 26,15, 14,15
  .byte 12,15, 12,15, 24,15, 12,15, 12,15, 12,15, 24,15, 12,15
  .byte 12,120
  .byte $FF
TITLE_DRUM:
  .byte 0,120, 0,120, 0,120, 0,120, 1,15, 3,15, 2,15, 3,15
  .byte 1,15, 3,15, 2,15, 3,15, 1,15, 3,15, 2,15, 3,15
  .byte 1,15, 3,15, 2,15, 3,15, 1,15, 3,15, 2,15, 3,15
  .byte 1,15, 3,15, 2,15, 3,15, 1,15, 3,15, 2,15, 3,15
  .byte 1,15, 3,15, 2,15, 3,15, 1,15, 3,15, 2,15, 3,15
  .byte 1,15, 2,7, 2,8, 2,8, 2,7, 2,7, 2,8, 4,120
  .byte $FF

; canzone di vittoria
WIN_LEAD:
  .byte 32,12, 37,12, 41,12, 44,36, 41,12, 44,12, 49,48, 44,24
  .byte 41,24, 42,12, 42,12, 42,12, 46,36, 44,12, 42,12, 41,48
  .byte 39,24, 36,24, 44,12, 41,12, 37,12, 44,12, 49,48, 49,12
  .byte 48,12, 49,72
  .byte $FF
WIN_HARM:
  .byte 29,12, 32,12, 37,12, 32,12, 29,12, 32,12, 37,12, 32,12
  .byte 29,12, 32,12, 37,12, 32,12, 29,12, 32,12, 37,12, 32,12
  .byte 30,12, 34,12, 37,12, 34,12, 30,12, 34,12, 37,12, 34,12
  .byte 27,12, 32,12, 36,12, 32,12, 27,12, 32,12, 36,12, 32,12
  .byte 29,12, 32,12, 37,12, 32,12, 29,12, 32,12, 37,12, 32,12
  .byte 32,96
  .byte $FF
WIN_BASS:
  .byte 13,12, 13,12, 25,12, 13,12, 13,12, 13,12, 25,12, 13,12
  .byte 13,12, 13,12, 25,12, 13,12, 13,12, 13,12, 25,12, 13,12
  .byte 6,12, 6,12, 18,12, 6,12, 6,12, 6,12, 18,12, 6,12
  .byte 8,12, 8,12, 20,12, 8,12, 8,12, 8,12, 20,12, 8,12
  .byte 13,12, 13,12, 25,12, 13,12, 13,12, 13,12, 25,12, 13,12
  .byte 13,96
  .byte $FF
WIN_DRUM:
  .byte 1,12, 3,12, 2,12, 3,12, 1,12, 3,12, 2,12, 3,12
  .byte 1,12, 3,12, 2,12, 3,12, 1,12, 3,12, 2,12, 3,12
  .byte 1,12, 3,12, 2,12, 3,12, 1,12, 3,12, 2,12, 3,12
  .byte 1,12, 3,12, 2,12, 3,12, 1,12, 3,12, 2,12, 3,12
  .byte 1,12, 3,12, 2,12, 3,12, 1,12, 3,12, 2,12, 3,12
  .byte 4,96
  .byte $FF
