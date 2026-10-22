;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;                                                              ;
;   ARCADE_004  -  CENTIPEDE                                   ;
;   65C02 assembly, TMS9918A Graphics II                       ;
;   Base: 1vs1 (NMI/vblank + SAT buffer + coda tile, VDP)      ;
;                                                              ;
;   - joystick su PORTA $D581 o PORTB $D580 (i due si sommano) ;
;   - joystick = muove il cannone nella zona in basso          ;
;   - un tasto qualsiasi (bit4 o bit5) = fuoco (un colpo alla  ;
;     volta, tenendo premuto riparte da solo)                  ;
;   - il centipede (12 segmenti) scende a zig-zag tra i funghi;;
;     un fungo regge 4 colpi; un segmento colpito diventa un   ;
;     fungo e quello dietro diventa una nuova testa            ;
;   - pulce (dal livello 2): cade lasciando funghi, 2 colpi    ;
;   - ragno: rimbalza nella zona del giocatore e mangia funghi ;
;   - punti: fungo 1, corpo 10, testa 100, pulce 200,          ;
;     ragno 300/600/900 (piu' e' vicino, piu' vale)            ;
;   - vita extra ogni 12000 punti; 3 vite; livelli infiniti    ;
;   - AUDIO su 2 x AY-3-8910: musica d'ingresso (il tasto si legge solo a
;     brano finito), 4 sibili diversi per lo sparo, esplosioni, suoni
;     diversi per fungo, corpo, testa, pulce e ragno, esplosione del
;     cannone, jingle di livello / vita extra e musica di sconfitta.
;     Il motore audio gira nell'NMI (60 Hz).
;   - il centipede e i funghi sono TILE (name table): le       ;
;     modifiche passano da una coda scritta dall'NMI nel vblank;
;     gli sprite (cannone, colpo, pulce, ragno, esplosione)    ;
;     passano dalla SAT come nel gioco di riferimento          ;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; ---------------- zero page (copia dei blocchi VDP) ----------------
VDP_INIT                 = $30
VDP_INIT_HI              = $31

; ---------------- zero page: stato di gioco ----------------
JOY                      = $60     ; joystick 1 + 2, 1 = premuto
PX                       = $61     ; cannone: X sprite (0-248)
PY                       = $62     ; cannone: Y del bordo alto (144-184)
BX                       = $63     ; colpo: X sprite
BY                       = $64     ; colpo: Y del bordo alto
BACT                     = $65     ; 1 = colpo in volo
LIVES                    = $66     ; vite (compresa quella in gioco)
LEVEL                    = $67
SC0                      = $68     ; punteggio BCD: SC2 SC1 SC0 (6 cifre)
SC1                      = $69
SC2                      = $6A
HI0                      = $6B     ; record BCD
HI1                      = $6C
HI2                      = $6D
NB1                      = $6E     ; prossima soglia di vita extra (BCD, SC2:SC1)
NB2                      = $6F
ALIVE                    = $70     ; segmenti vivi
STEPCNT                  = $71     ; frame al prossimo passo del centipede
STEPLEN                  = $72     ; frame per passo
ANIM                     = $73     ; fase delle zampe
DYING                    = $74     ; frame rimasti di esplosione del cannone
LVLTMR                   = $75     ; pausa prima del livello successivo
HUDDIRTY                 = $76
RND                      = $77
QN                       = $78     ; voci in costruzione nella coda tile
QGO                      = $79     ; voci pubblicate (le consuma l'NMI)
FACT                     = $7A     ; pulce attiva
FX                       = $7B
FY                       = $7C
FHP                      = $7D     ; colpi che le mancano
FSPD                     = $7E
FTMR                     = $7F     ; attesa pulce (unita' di 16 frame)
SACT                     = $80     ; ragno attivo
SX                       = $81
SY                       = $82
SDX                      = $83     ; 0 = va a destra, 1 = a sinistra
SVY                      = $84     ; 0 = sale, 1 = scende
STMR                     = $85     ; attesa ragno (unita' di 16 frame)
GO_DELAY                 = $86
ARMED                    = $87
T0                       = $90
T1                       = $91
T2                       = $92
T3                       = $93
T4                       = $94
T5                       = $95
T6                       = $96
T7                       = $97
PTR                      = $98     ; 2 byte
MPTR                     = $9A     ; 2 byte: indirizzo nel MAP
T8                       = $9C
T9                       = $9D

; ---------------- zero page: audio (usate dal motore nell'NMI) ----------------
SFX_REQ                  = $A0     ; effetto richiesto (id+1, 0 = nessuno)
SFX_RPRI                 = $A1     ; priorita' della richiesta
SFX_CNT                  = $A2     ; frame rimasti dell'effetto in corso
SFX_PRI                  = $A3
SFX_MODE                 = $A4     ; bit0 = tono, bit1 = rumore
SFX_PL                   = $A5     ; periodo del tono (16 bit)
SFX_PH                   = $A6
SFX_DEL                  = $A7     ; variazione del periodo per frame (con segno)
SFX_VOL                  = $A8
SFX_DEC                  = $A9     ; ogni quanti frame cala il volume
SFX_DCNT                 = $AA
SFX_NP                   = $AB     ; periodo del rumore
SFX_FLIP                 = $AC     ; ogni quanti frame inverte il delta (vibrato)
SFX_FCNT                 = $AD
MUS_ON                   = $AE     ; <> 0 finche' un brano sta suonando
; due voci musicali, 8 byte ciascuna: PTR(2) CNT TPL TPH VOL NOTE ACT
MEL_PTR                  = $B0
MEL_CNT                  = $B2
MEL_TPL                  = $B3
MEL_TPH                  = $B4
MEL_VOL                  = $B5
MEL_NOTE                 = $B6
MEL_ACT                  = $B7
BAS_PTR                  = $B8
BAS_CNT                  = $BA
BAS_TPL                  = $BB
BAS_TPH                  = $BC
BAS_VOL                  = $BD
BAS_NOTE                 = $BE
BAS_ACT                  = $BF
NT0                      = $C0
NT1                      = $C1
NT2                      = $C2
NT3                      = $C3

; AY-3-8910 (stereo, come SUPER_MARIO_STEREO.s): LATCH = registro, WRITE = dato
AY_L_LATCH = $D384
AY_L_WRITE = $D385
AY_R_LATCH = $D380
AY_R_WRITE = $D381

PORTB_JOY = $d580        ;         |P2|P1|RG|LF|DW|UP (LSB)   joystick 2
PORTA_JOY = $d581        ;         |P2|P1|RG|LF|DW|UP (LSB)   joystick 1
DDRB_JOY  = $d582        ;
DDRA_JOY  = $d583        ;

; ---------------- RAM di lavoro (sopra il programma) ----------------
MAPBASE   = $5000        ; 32x24 byte: 0 = vuoto, 1-4 = fungo (4 = intero); riga 0 = HUD
SCOL      = $5300        ; segmenti del centipede (16 posti, se ne usano 12)
SROW      = $5310
SDIR      = $5320        ; 0 = va a destra, 1 = a sinistra
SHEAD     = $5330        ; 1 = testa
SALIVE    = $5340
SUP       = $5350        ; 1 = sta risalendo nella zona del giocatore
QLO       = $5400        ; coda tile: indirizzo VRAM basso, alto (con bit di scrittura), tile
QHI       = $5440
QTL       = $5480
LBUF      = $5500        ; registri AY da scrivere nel frame: chip sinistro (9) ...
RBUF      = $5510        ; ... e destro (9)

; ---------------- parametri di gioco ----------------
NSEG          = 12       ; segmenti totali (catena + teste singole)
PSPEED        = 2        ; pixel per frame del cannone
BSPEED        = 4        ; pixel per frame del colpo
PY_MIN        = 144      ; zona del giocatore: righe 18-23
PY_MAX        = 184
PZ_TOP        = 18       ; prima riga della zona del giocatore
QMAX          = 64       ; voci massime nella coda
MUSH_COUNT    = 42       ; funghi iniziali
START_LIVES   = 3
DEATH_FRAMES  = 90
HIDE_Y        = $C0      ; Y fuori schermo (NON $D0: fermerebbe la lista sprite)
BTN_MASK      = %00110000
BLOCK_COUNT   = 7        ; blocchi in VDP_BLOCKS

; tile
T_BODY        = $05      ; $05/$06 = corpo (due fasi di zampe)
T_HEAD_R      = $07
T_HEAD_L      = $08
T_LIFE        = $0E

; effetti sonori (indice in SFX_TAB)
SFX_SHOT0     = 0        ; 0-3: quattro sibili diversi per lo sparo
SFX_HIT       = 4        ; fungo colpito
SFX_POP       = 5        ; fungo distrutto
SFX_BODY      = 6        ; segmento di corpo
SFX_HEAD      = 7        ; testa
SFX_FLEA      = 8        ; pulce uccisa
SFX_SPIDER    = 9        ; ragno ucciso
SFX_BOOM      = 10       ; esplosione del cannone
SFX_FLEAHIT   = 11       ; pulce colpita (non ancora morta)

; brani (indice in SONG_TAB)
SONG_TITLE    = 0
SONG_OVER     = 1
SONG_LEVEL    = 2
SONG_LIFE     = 3


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
  STA HI0
  STA HI1
  STA HI2
  STA HUDDIRTY
  LDA #$A5
  STA RND
  JSR HIDE_SPRITES
  JSR SND_INIT

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
  LDA #$00
  STA QN
  STA QGO
  JSR SND_STOP
  JSR HIDE_SPRITES
  JSR VDP_INT_OFF              ; da ora il main loop puo' scrivere sul VDP
  JSR CLEAR_NAME_TABLE
  LDA #<TITLE_REC
  STA PTR
  LDA #>TITLE_REC
  STA PTR+1
  JSR DRAW_RECORDS
  JSR VDP_INT_ON
  LDX #SONG_TITLE              ; musica d'ingresso: il tasto si legge solo alla fine
  JSR PLAY_SONG
.ti_w:
  JSR WAIT_FRAME
  LDA MUS_ON
  BNE .ti_w
  JSR VDP_INT_OFF
  LDA #<PRESS_REC
  STA PTR
  LDA #>PRESS_REC
  STA PTR+1
  JSR DRAW_RECORDS
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
  JSR SND_STOP
  LDA #$00
  STA SC0
  STA SC1
  STA SC2
  STA DYING
  STA LVLTMR
  STA QN
  STA QGO
  LDA #$20                     ; prima vita extra a 12000
  STA NB1
  LDA #$01
  STA NB2
  LDA #START_LIVES
  STA LIVES
  LDA #$01
  STA LEVEL
  JSR HIDE_SPRITES
  JSR CLEAR_MAP
  JSR GEN_MUSH
  JSR VDP_INT_OFF
  JSR DRAW_FIELD
  JSR VDP_INT_ON
  JSR INIT_PLAYER
  JSR INIT_LEVEL
  JSR HUD_PUSH                 ; punteggi, vite, livello (via coda)

GAME_LOOP:
  JSR READ_JOY
  LDA DYING
  BEQ .gl_play
  JSR DYING_STEP
  BRA .gl_draw
.gl_play:
  JSR NEXT_RND
  JSR UPDATE_PLAYER
  JSR UPDATE_BULLET
  JSR UPDATE_FLEA
  JSR UPDATE_SPIDER
  JSR UPDATE_CENTI
  JSR CHECK_PLAYER_HIT
  JSR LEVEL_CHECK
.gl_draw:
  JSR DRAW_SPRITES
  LDA HUDDIRTY
  BEQ .gl_pub
  LDA #$00
  STA HUDDIRTY
  JSR HUD_PUSH
.gl_pub:
  LDA QN                       ; pubblica la coda: la consuma l'NMI nel vblank
  STA QGO
  LDA #$00
  STA QN
  JSR WAIT_FRAME               ; sincronizza il loop al vblank (NMI)
.gl_qw:
  LDA QGO                      ; aspetta che la coda sia stata scritta
  BNE .gl_qw
  JMP GAME_LOOP


; ---------------------------------------------------------------
; legge i due joystick (1 = premuto) e li somma
; ---------------------------------------------------------------
READ_JOY:
  LDA PORTA_JOY
  EOR #$FF
  AND #$3F
  STA JOY
  LDA PORTB_JOY
  EOR #$FF
  AND #$3F
  ORA JOY
  STA JOY
  RTS


NEXT_RND:                      ; LFSR a 8 bit
  LDA RND
  ASL A
  BCC .nr_ok
  EOR #$1D
.nr_ok:
  STA RND
  RTS

RND8:                          ; 8 passi: A = byte "fresco" (X preservato)
  PHX
  LDX #8
.r8:
  JSR NEXT_RND
  DEX
  BNE .r8
  PLX
  LDA RND
  RTS


; ---------------------------------------------------------------
; coda dei tile: A = tile, T0/T1 = indirizzo VRAM (lo, hi con bit $40)
; (Y viene modificato)
; ---------------------------------------------------------------
QPUT:
  LDY QN
  CPY #QMAX
  BCS .qp_full
  STA QTL,Y
  LDA T0
  STA QLO,Y
  LDA T1
  STA QHI,Y
  INC QN
.qp_full:
  RTS

; riga A, colonna Y  ->  MPTR = indirizzo nel MAP, T0/T1 = indirizzo VRAM (name table)
; (X e Y preservati)
CALC_CELL:
  PHA
  LSR A
  LSR A
  LSR A
  STA T2                       ; riga / 8
  CLC
  ADC #>MAPBASE
  STA MPTR+1
  LDA T2
  CLC
  ADC #(VDP_WRITE_VRAM_BIT | >VDP_NAME_TABLE_BASE)
  STA T1
  PLA
  AND #$07
  ASL A
  ASL A
  ASL A
  ASL A
  ASL A                        ; (riga mod 8) * 32
  STA T0
  TYA
  ORA T0
  STA T0
  STA MPTR
  RTS


; ---------------------------------------------------------------
; punteggio: T0 = punti BCD (decine/unita'), T1 = BCD (migliaia/centinaia)
; gestisce vita extra e record
; ---------------------------------------------------------------
ADD_SCORE:
  SED
  CLC
  LDA SC0
  ADC T0
  STA SC0
  LDA SC1
  ADC T1
  STA SC1
  LDA SC2
  ADC #$00
  STA SC2
  CLD
  LDA SC2                      ; vita extra?
  CMP NB2
  BCC .as_nob
  BNE .as_bon
  LDA SC1
  CMP NB1
  BCC .as_nob
.as_bon:
  PHX
  PHY
  LDX #SONG_LIFE               ; jingle della vita extra
  JSR PLAY_SONG
  PLY
  PLX
  LDA LIVES
  CMP #9
  BCS .as_nl
  INC LIVES
.as_nl:
  SED
  CLC
  LDA NB1
  ADC #$20
  STA NB1
  LDA NB2
  ADC #$01
  STA NB2
  CLD
.as_nob:
  LDA SC2                      ; nuovo record?
  CMP HI2
  BCC .as_hid
  BNE .as_hi
  LDA SC1
  CMP HI1
  BCC .as_hid
  BNE .as_hi
  LDA SC0
  CMP HI0
  BCC .as_hid
.as_hi:
  LDA SC0
  STA HI0
  LDA SC1
  STA HI1
  LDA SC2
  STA HI2
.as_hid:
  LDA #$01
  STA HUDDIRTY
  RTS


; ---------------------------------------------------------------
; HUD via coda: punteggio (col 1-6), vite (8-13), livello (17-18), record (24-29)
; ---------------------------------------------------------------
HUD_PUSH:
  LDX #1
  LDA SC2
  JSR PUSH_BCD
  LDA SC1
  JSR PUSH_BCD
  LDA SC0
  JSR PUSH_BCD
  LDX #8                       ; icone delle vite di riserva
  LDY #0
.hp_l:
  STY T9
  LDA T9
  CLC
  ADC #1
  CMP LIVES                    ; icona se (k+1) < LIVES
  BCS .hp_no
  LDA #T_LIFE
  BRA .hp_p
.hp_no:
  LDA #$00
.hp_p:
  JSR PUSH_COL
  LDY T9
  INY
  CPY #6
  BNE .hp_l
  LDX #17                      ; livello a due cifre
  LDA LEVEL
  LDY #0
.hp_d:
  CMP #10
  BCC .hp_o
  SBC #10
  INY
  BRA .hp_d
.hp_o:
  STA T8                       ; unita'
  TYA
  BEQ .hp_t0
  CLC
  ADC #$30
  BRA .hp_t
.hp_t0:
  LDA #$00
.hp_t:
  JSR PUSH_COL
  LDA T8
  CLC
  ADC #$30
  JSR PUSH_COL
  LDX #24
  LDA HI2
  JSR PUSH_BCD
  LDA HI1
  JSR PUSH_BCD
  LDA HI0
  JMP PUSH_BCD

; A = byte BCD, X = colonna (riga 0): scrive 2 cifre, X avanza di 2
PUSH_BCD:
  STA T3
  LSR A
  LSR A
  LSR A
  LSR A
  CLC
  ADC #$30
  JSR PUSH_COL
  LDA T3
  AND #$0F
  CLC
  ADC #$30
; A = tile, X = colonna sulla riga 0: X avanza di 1
PUSH_COL:
  STX T0
  LDY #(VDP_WRITE_VRAM_BIT | >VDP_NAME_TABLE_BASE)
  STY T1
  JSR QPUT
  INX
  RTS


; ---------------------------------------------------------------
; MAP
; ---------------------------------------------------------------
CLEAR_MAP:
  LDA #<MAPBASE
  STA MPTR
  LDA #>MAPBASE
  STA MPTR+1
  LDX #3                       ; 768 byte
.cm_p:
  LDY #0
  LDA #$00
.cm_b:
  STA (MPTR),Y
  INY
  BNE .cm_b
  INC MPTR+1
  DEX
  BNE .cm_p
  RTS

GEN_MUSH:                      ; funghi a caso nelle righe 2-17
  LDX #MUSH_COUNT
.gm_l:
  JSR RND8
  AND #$1F
  STA T4
  JSR RND8
  AND #$0F
  CLC
  ADC #2
  LDY T4
  JSR CALC_CELL
  LDA #4
  STA (MPTR)
  DEX
  BNE .gm_l
  RTS

; riga HUD fissa + campo (MAP righe 1-23) nella name table. VDP libero (INT off).
DRAW_FIELD:
  LDA #$00
  STA VREG
  LDA #(VDP_WRITE_VRAM_BIT | >VDP_NAME_TABLE_BASE)
  STA VREG
  LDY #0
.df_h:
  LDA HUD_STATIC,Y
  STA VDATA
  INY
  CPY #32
  BNE .df_h
  LDA #<(MAPBASE+32)
  STA PTR
  LDA #>(MAPBASE+32)
  STA PTR+1
  LDX #2                       ; 512 byte ...
.df_p:
  LDY #0
.df_b:
  LDA (PTR),Y
  STA VDATA
  INY
  BNE .df_b
  INC PTR+1
  DEX
  BNE .df_p
  LDY #0                       ; ... + 224 = 736 = righe 1-23
.df_t:
  LDA (PTR),Y
  STA VDATA
  INY
  CPY #224
  BNE .df_t
  RTS


; ---------------------------------------------------------------
; giocatore
; ---------------------------------------------------------------
INIT_PLAYER:
  LDA #124
  STA PX
  LDA #PY_MAX
  STA PY
  LDA #$00
  STA BACT
  STA DYING
  RTS

; T4 = x, T5 = y (sprite): A <> 0 (Z=0) se la scatola 6x6 tocca un fungo
BOX_BLOCKED:
  LDA T4
  CLC
  ADC #1
  LSR A
  LSR A
  LSR A
  STA T6                       ; colonna sinistra
  LDA T4
  CLC
  ADC #6
  LSR A
  LSR A
  LSR A
  STA T7                       ; colonna destra
  LDA T5
  CLC
  ADC #1
  LSR A
  LSR A
  LSR A
  STA T8                       ; riga alta
  LDA T5
  CLC
  ADC #6
  LSR A
  LSR A
  LSR A
  STA T9                       ; riga bassa
  LDY T6
  LDA T8
  JSR CALC_CELL
  LDA (MPTR)
  BNE .bb_end
  LDY T7
  LDA T8
  JSR CALC_CELL
  LDA (MPTR)
  BNE .bb_end
  LDY T6
  LDA T9
  JSR CALC_CELL
  LDA (MPTR)
  BNE .bb_end
  LDY T7
  LDA T9
  JSR CALC_CELL
  LDA (MPTR)
.bb_end:
  RTS

UPDATE_PLAYER:
  LDA JOY
  AND #%00001000               ; destra
  BEQ .up_nr
  LDA PX
  CLC
  ADC #PSPEED
  CMP #249
  BCS .up_nr
  STA T4
  LDA PY
  STA T5
  JSR BOX_BLOCKED
  BNE .up_nr
  LDA T4
  STA PX
.up_nr:
  LDA JOY
  AND #%00000100               ; sinistra
  BEQ .up_nl
  LDA PX
  SEC
  SBC #PSPEED
  BCC .up_nl
  STA T4
  LDA PY
  STA T5
  JSR BOX_BLOCKED
  BNE .up_nl
  LDA T4
  STA PX
.up_nl:
  LDA JOY
  AND #%00000001               ; su
  BEQ .up_nu
  LDA PY
  SEC
  SBC #PSPEED
  CMP #PY_MIN
  BCC .up_nu
  STA T5
  LDA PX
  STA T4
  JSR BOX_BLOCKED
  BNE .up_nu
  LDA T5
  STA PY
.up_nu:
  LDA JOY
  AND #%00000010               ; giu'
  BEQ .up_nd
  LDA PY
  CLC
  ADC #PSPEED
  CMP #(PY_MAX+1)
  BCS .up_nd
  STA T5
  LDA PX
  STA T4
  JSR BOX_BLOCKED
  BNE .up_nd
  LDA T5
  STA PY
.up_nd:
  RTS


; ---------------------------------------------------------------
; colpo
; ---------------------------------------------------------------
UPDATE_BULLET:
  LDA BACT
  BNE .ub_act
  LDA JOY                      ; fuoco: un colpo alla volta
  AND #BTN_MASK
  BEQ .ub_end
  LDA #$01
  STA BACT
  LDA PX
  STA BX
  LDA PY
  SEC
  SBC #8
  STA BY
  LDA RND                      ; uno dei 4 sibili
  AND #$03
  JSR SFX
  RTS
.ub_act:
  LDA BY
  SEC
  SBC #BSPEED
  STA BY
  CMP #8
  BCS .ub_t
  LDA #$00                     ; uscito in cima
  STA BACT
  RTS
.ub_t:
  JMP BULLET_TEST
.ub_end:
  RTS

; il colpo e' attivo: controlla pulce, ragno, segmenti, funghi
BULLET_TEST:
  LDA FACT                     ; --- pulce: x in [FX-4, FX+4], y in [FY-7, FY+15]
  BEQ .bt_nf
  LDA BX
  SEC
  SBC FX
  CLC
  ADC #4
  CMP #9
  BCS .bt_nf
  LDA BY
  SEC
  SBC FY
  CLC
  ADC #7
  CMP #23
  BCS .bt_nf
  LDA #$00
  STA BACT
  DEC FHP
  BEQ .bt_fdead
  LDA #3                       ; primo colpo: piu' veloce
  STA FSPD
  LDA #SFX_FLEAHIT
  JSR SFX
  RTS
.bt_fdead:
  LDA #$00
  STA FACT
  STA T0
  LDA #$02                     ; 200 punti
  STA T1
  JSR ADD_SCORE
  LDA #SFX_FLEA
  JSR SFX
  JMP FLEA_RELOAD
.bt_nf:
  LDA SACT                     ; --- ragno: x in [SX-4, SX+12], y in [SY-7, SY+7]
  BEQ .bt_ns
  LDA BX
  SEC
  SBC SX
  CLC
  ADC #4
  CMP #17
  BCS .bt_ns
  LDA BY
  SEC
  SBC SY
  CLC
  ADC #7
  CMP #15
  BCS .bt_ns
  LDA #$00
  STA BACT
  STA SACT
  LDA PY                       ; piu' e' vicino, piu' vale
  SEC
  SBC SY
  BCS .bt_sd
  EOR #$FF
  CLC
  ADC #1
.bt_sd:
  STA T4
  LDA #$00
  STA T0
  LDA T4
  CMP #16
  BCC .bt_s9
  CMP #32
  BCC .bt_s6
  LDA #$03
  BRA .bt_ss
.bt_s6:
  LDA #$06
  BRA .bt_ss
.bt_s9:
  LDA #$09
.bt_ss:
  STA T1
  JSR ADD_SCORE
  LDA #SFX_SPIDER
  JSR SFX
  JMP SPIDER_RELOAD
.bt_ns:
  LDA BX                       ; --- cella del colpo
  CLC
  ADC #4
  LSR A
  LSR A
  LSR A
  STA T4                       ; colonna
  TAY
  LDA BY
  LSR A
  LSR A
  LSR A
  STA T5                       ; riga
  LDX #0
.bt_s:
  LDA SALIVE,X
  BEQ .bt_sn
  LDA SCOL,X
  CMP T4
  BNE .bt_sn
  LDA SROW,X
  CMP T5
  BNE .bt_sn
  JMP SEG_HIT
.bt_sn:
  INX
  CPX #NSEG
  BNE .bt_s
  LDA T5                       ; --- fungo
  LDY T4
  JSR CALC_CELL
  LDA (MPTR)
  BEQ .bt_end
  SEC
  SBC #1
  STA (MPTR)
  PHA
  JSR QPUT                     ; ridisegna il fungo (tile = vita residua)
  PLA
  BNE .bt_hit
  LDA #$01                     ; fungo distrutto: 1 punto
  STA T0
  LDA #$00
  STA T1
  JSR ADD_SCORE
  LDA #SFX_POP
  BRA .bt_snd
.bt_hit:
  LDA #SFX_HIT
.bt_snd:
  JSR SFX
.bt_stop:
  LDA #$00
  STA BACT
.bt_end:
  RTS

; segmento X colpito: diventa un fungo, quello dietro diventa testa
SEG_HIT:
  LDA #$00
  STA BACT
  STA SALIVE,X
  DEC ALIVE
  LDA SHEAD,X
  BNE .sh_head
  LDA #$10                     ; corpo: 10
  STA T0
  LDA #$00
  STA T1
  LDA #SFX_BODY
  JSR SFX
  BRA .sh_sc
.sh_head:
  LDA #$00                     ; testa: 100
  STA T0
  LDA #$01
  STA T1
  LDA #SFX_HEAD
  JSR SFX
.sh_sc:
  JSR ADD_SCORE
  INX
  CPX #NSEG
  BEQ .sh_nx
  LDA SALIVE,X
  BEQ .sh_nx
  LDA #$01
  STA SHEAD,X
.sh_nx:
  DEX
  LDA SROW,X
  LDY SCOL,X
  JSR CALC_CELL
  LDA #4
  STA (MPTR)
  JMP QPUT


; ---------------------------------------------------------------
; centipede
; ---------------------------------------------------------------
UPDATE_CENTI:
  LDA ALIVE
  BEQ .uc_end
  DEC STEPCNT
  BNE .uc_end
  LDA STEPLEN
  STA STEPCNT
  JSR CENTI_STEP
  LDA BACT                     ; dopo il passo il colpo puo' toccare un segmento
  BEQ .uc_end
  JSR BULLET_TEST
.uc_end:
  RTS

CENTI_STEP:
  LDA ANIM
  EOR #$01
  STA ANIM
  LDX #0                       ; A: ridisegna le vecchie celle dal MAP
.cs_e:
  LDA SALIVE,X
  BEQ .cs_en
  LDA SROW,X
  LDY SCOL,X
  JSR CALC_CELL
  LDA (MPTR)
  JSR QPUT
.cs_en:
  INX
  CPX #NSEG
  BNE .cs_e
  LDX #(NSEG-1)                ; B: dalla coda alla testa
.cs_m:
  LDA SALIVE,X
  BEQ .cs_mn
  LDA SHEAD,X
  BNE .cs_head
  LDA SCOL-1,X                 ; seguace: va dove stava il precedente
  STA SCOL,X
  LDA SROW-1,X
  STA SROW,X
  LDA SDIR-1,X
  STA SDIR,X
  LDA SUP-1,X
  STA SUP,X
  BRA .cs_mn
.cs_head:
  JSR HEAD_MOVE
.cs_mn:
  DEX
  BPL .cs_m
  LDX #0                       ; C: disegna le nuove celle
.cs_d:
  LDA SALIVE,X
  BEQ .cs_dn
  JSR PUSH_SEG
.cs_dn:
  INX
  CPX #NSEG
  BNE .cs_d
  RTS

; muove la testa X (X preservato)
HEAD_MOVE:
  LDA SDIR,X
  BNE .hm_left
  LDA SCOL,X
  CLC
  ADC #1
  BRA .hm_test
.hm_left:
  LDA SCOL,X
  SEC
  SBC #1
.hm_test:
  STA T4
  CMP #32
  BCS .hm_blk                  ; fuori dallo schermo (anche $FF)
  TAY
  LDA SROW,X
  JSR CALC_CELL
  LDA (MPTR)
  BNE .hm_blk                  ; fungo
  LDA T4
  STA SCOL,X
  RTS
.hm_blk:
  LDA SDIR,X                   ; bloccata: inverte e cambia riga
  EOR #$01
  STA SDIR,X
  LDA SUP,X
  BNE .hm_up
  LDA SROW,X
  CMP #23
  BEQ .hm_tu
  INC SROW,X
  RTS
.hm_tu:                        ; in fondo: comincia a risalire
  LDA #$01
  STA SUP,X
  DEC SROW,X
  RTS
.hm_up:
  LDA SROW,X
  CMP #(PZ_TOP+1)
  BCS .hm_gu
  LDA #$00                     ; in cima alla zona del giocatore: torna a scendere
  STA SUP,X
  INC SROW,X
  RTS
.hm_gu:
  DEC SROW,X
  RTS

; accoda il tile del segmento X
PUSH_SEG:
  LDA SROW,X
  LDY SCOL,X
  JSR CALC_CELL
  LDA SHEAD,X
  BEQ .ps_body
  LDA SDIR,X
  BNE .ps_hl
  LDA #T_HEAD_R
  JMP QPUT
.ps_hl:
  LDA #T_HEAD_L
  JMP QPUT
.ps_body:
  TYA
  CLC
  ADC ANIM
  AND #$01
  CLC
  ADC #T_BODY
  JMP QPUT

; nuovo centipede per LEVEL: catena di (13-L) segmenti + (L-1) teste singole
INIT_LEVEL:
  LDA LEVEL
  CMP #13
  BCC .il_l
  LDA #12
.il_l:
  STA T4                       ; livello efficace 1-12
  LDA #13
  SEC
  SBC T4
  STA T5                       ; lunghezza della catena
  LDX #0
.il_s:
  LDA #$01
  STA SALIVE,X
  STA SROW,X
  LDA #$00
  STA SUP,X
  CPX T5
  BCS .il_ex
  LDA #$00                     ; catena: testa a destra, corpo a sinistra
  STA SDIR,X
  STX T6
  LDA T5
  SEC
  SBC #1
  SEC
  SBC T6
  STA SCOL,X
  LDA #$00
  CPX #0
  BNE .il_h
  LDA #$01
.il_h:
  STA SHEAD,X
  BRA .il_n
.il_ex:                        ; teste singole: dal bordo destro, verso sinistra
  LDA #$01
  STA SDIR,X
  STA SHEAD,X
  TXA
  SEC
  SBC T5
  ASL A
  STA T6
  LDA #31
  SEC
  SBC T6
  STA SCOL,X
.il_n:
  INX
  CPX #NSEG
  BNE .il_s
  LDA #NSEG
  STA ALIVE
  LDA #$00
  STA ANIM
  STA FACT
  STA SACT
  STA LVLTMR
  LDY T4
  LDA STEP_TAB-1,Y
  STA STEPLEN
  STA STEPCNT
  LDA #30
  STA FTMR
  LDA #40
  STA STMR
  LDX #0
.il_d:
  JSR PUSH_SEG
  INX
  CPX #NSEG
  BNE .il_d
  RTS

STEP_TAB:                      ; frame per passo, livelli 1-12
  .byte 6,5,5,4,4,4,3,3,3,2,2,2

LEVEL_CHECK:
  LDA LVLTMR
  BNE .lc_wait
  LDA ALIVE
  BNE .lc_end
  LDA #90                      ; centipede eliminato: breve pausa
  STA LVLTMR
  LDX #SONG_LEVEL
  JSR PLAY_SONG
  LDA #$00
  STA FACT
  STA SACT
  RTS
.lc_wait:
  DEC LVLTMR
  BNE .lc_end
  LDA LEVEL
  CMP #99
  BCS .lc_nl
  INC LEVEL
.lc_nl:
  JSR INIT_LEVEL
  LDA #$01
  STA HUDDIRTY
.lc_end:
  RTS


; ---------------------------------------------------------------
; pulce
; ---------------------------------------------------------------
FLEA_RELOAD:
  JSR RND8
  AND #$1F
  CLC
  ADC #24
  STA FTMR
  RTS

UPDATE_FLEA:
  LDA FACT
  BNE .uf_move
  LDA LEVEL                    ; dal livello 2
  CMP #2
  BCC .uf_end
  LDA FRAME_CNT
  AND #$0F
  BNE .uf_end
  LDA FTMR
  BEQ .uf_spawn
  DEC FTMR
  BNE .uf_end
.uf_spawn:
  JSR RND8
  AND #$1F
  ASL A
  ASL A
  ASL A
  STA FX
  LDA #8
  STA FY
  LDA #2
  STA FHP
  STA FSPD
  LDA #$01
  STA FACT
.uf_end:
  RTS
.uf_move:
  LDA FY
  LSR A
  LSR A
  LSR A
  STA T4                       ; riga prima del passo
  LDA FY
  CLC
  ADC FSPD
  STA FY
  CMP #192
  BCS .uf_gone
  LSR A
  LSR A
  LSR A
  CMP T4
  BEQ .uf_end
  CMP #2
  BCC .uf_end
  CMP #23
  BCS .uf_end
  STA T5                       ; nuova riga: forse lascia un fungo
  JSR RND8
  CMP #100
  BCS .uf_end
  LDA FX
  LSR A
  LSR A
  LSR A
  TAY
  LDA T5
  JSR CALC_CELL
  LDA (MPTR)
  BNE .uf_end
  LDA #4
  STA (MPTR)
  JMP QPUT
.uf_gone:
  LDA #$00
  STA FACT
  JMP FLEA_RELOAD


; ---------------------------------------------------------------
; ragno
; ---------------------------------------------------------------
SPIDER_RELOAD:
  JSR RND8
  AND #$1F
  CLC
  ADC #20
  STA STMR
  RTS

UPDATE_SPIDER:
  LDA SACT
  BNE .us_move
  LDA FRAME_CNT
  AND #$0F
  BNE .us_end
  LDA STMR
  BEQ .us_spawn
  DEC STMR
  BNE .us_end
.us_spawn:
  JSR RND8
  STA T4
  AND #$01
  BNE .us_fromr
  LDA #$00                     ; entra da sinistra
  STA SX
  STA SDX
  BRA .us_y
.us_fromr:
  LDA #240                     ; entra da destra
  STA SX
  LDA #$01
  STA SDX
.us_y:
  LDA T4
  LSR A
  LSR A
  AND #$1F
  CLC
  ADC #PY_MIN
  STA SY
  LDA T4
  LSR A
  LSR A
  LSR A
  LSR A
  LSR A
  AND #$01
  STA SVY
  LDA #$01
  STA SACT
.us_end:
  RTS
.us_move:
  LDA SDX
  BNE .us_l
  INC SX
  LDA SX
  CMP #240
  BCS .us_gone
  BRA .us_v
.us_l:
  DEC SX
  BEQ .us_gone
.us_v:
  LDA FRAME_CNT                ; ogni tanto cambia verso in verticale
  AND #$0F
  BNE .us_mv
  JSR NEXT_RND
  LDA RND
  AND #$03
  BNE .us_mv
  LDA SVY
  EOR #$01
  STA SVY
.us_mv:
  LDA SVY
  BNE .us_dn
  DEC SY
  LDA SY
  CMP #PY_MIN
  BCS .us_eat
  LDA #$01
  STA SVY
  BRA .us_eat
.us_dn:
  INC SY
  LDA SY
  CMP #PY_MAX
  BCC .us_eat
  LDA #$00
  STA SVY
.us_eat:
  LDA SY                       ; mangia il fungo sotto il centro
  CLC
  ADC #4
  LSR A
  LSR A
  LSR A
  STA T5
  CMP #PZ_TOP
  BCC .us_end
  LDA SX
  CLC
  ADC #8
  LSR A
  LSR A
  LSR A
  TAY
  LDA T5
  JSR CALC_CELL
  LDA (MPTR)
  BEQ .us_end
  LDA #$00
  STA (MPTR)
  JMP QPUT
.us_gone:
  LDA #$00
  STA SACT
  JMP SPIDER_RELOAD


; ---------------------------------------------------------------
; il cannone viene toccato
; ---------------------------------------------------------------
CHECK_PLAYER_HIT:
  LDA PX
  CLC
  ADC #1
  LSR A
  LSR A
  LSR A
  STA T4                       ; colonne toccate dal cannone
  LDA PX
  CLC
  ADC #6
  LSR A
  LSR A
  LSR A
  STA T5
  LDA PY
  CLC
  ADC #1
  LSR A
  LSR A
  LSR A
  STA T6                       ; righe toccate
  LDA PY
  CLC
  ADC #6
  LSR A
  LSR A
  LSR A
  STA T7
  LDX #0
.ph_s:
  LDA SALIVE,X
  BEQ .ph_n
  LDA SCOL,X
  CMP T4
  BCC .ph_n
  CMP T5
  BEQ .ph_c
  BCS .ph_n
.ph_c:
  LDA SROW,X
  CMP T6
  BCC .ph_n
  CMP T7
  BEQ .ph_hit
  BCC .ph_hit
.ph_n:
  INX
  CPX #NSEG
  BNE .ph_s
  LDA FACT                     ; pulce
  BEQ .ph_nf
  LDA PX
  SEC
  SBC FX
  CLC
  ADC #6
  CMP #13
  BCS .ph_nf
  LDA PY
  SEC
  SBC FY
  CLC
  ADC #6
  CMP #21
  BCC .ph_hit
.ph_nf:
  LDA SACT                     ; ragno
  BEQ .ph_end
  LDA PX
  SEC
  SBC SX
  CLC
  ADC #6
  CMP #21
  BCS .ph_end
  LDA PY
  SEC
  SBC SY
  CLC
  ADC #6
  CMP #13
  BCC .ph_hit
.ph_end:
  RTS
.ph_hit:
  LDA #DEATH_FRAMES
  STA DYING
  LDA #SFX_BOOM
  JSR SFX
  LDA #$00
  STA BACT
  RTS

DYING_STEP:
  DEC DYING
  BNE .ds_end
  DEC LIVES
  BEQ .ds_over
  JMP RESPAWN
.ds_over:
  JMP GAME_OVER
.ds_end:
  RTS

; riparte con una vita in meno: funghi riparati (+5 punti l'uno), nuovo centipede
RESPAWN:
  LDA #<MAPBASE
  STA MPTR
  LDA #>MAPBASE
  STA MPTR+1
  LDX #3
.rs_p:
  LDY #0
.rs_b:
  LDA (MPTR),Y
  BEQ .rs_n
  CMP #4
  BEQ .rs_n
  LDA #4
  STA (MPTR),Y
  LDA #$05
  STA T0
  LDA #$00
  STA T1
  JSR ADD_SCORE
.rs_n:
  INY
  BNE .rs_b
  INC MPTR+1
  DEX
  BNE .rs_p
  JSR VDP_INT_OFF
  JSR DRAW_FIELD
  JSR VDP_INT_ON
  JSR INIT_PLAYER
  JSR INIT_LEVEL
  LDA #$01
  STA HUDDIRTY
  RTS


; ===============================================================
;  FINE PARTITA
; ===============================================================
GAME_OVER:
  LDX #$FF
  TXS
  LDA #$00
  STA QN
  STA QGO
  JSR HIDE_SPRITES
  JSR VDP_INT_OFF
  LDA #<OVER_REC
  STA PTR
  LDA #>OVER_REC
  STA PTR+1
  JSR DRAW_RECORDS
  JSR VDP_INT_ON
  LDX #SONG_OVER               ; musica di sconfitta: il tasto si legge solo alla fine
  JSR PLAY_SONG
.go_mus:
  JSR WAIT_FRAME
  LDA MUS_ON
  BNE .go_mus
  LDA #$00
  STA ARMED
  LDA #45                      ; poi un breve intervallo prima di accettare il pulsante
  STA GO_DELAY
.go_loop:
  JSR WAIT_FRAME
  JSR READ_JOY
  LDA JOY
  AND #BTN_MASK
  BNE .go_pressed
  LDA GO_DELAY                 ; pulsanti rilasciati: conta l'attesa, poi arma
  BNE .go_dec
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
  LDA JOY
  AND #BTN_MASK
  BNE .wf_rel
.wf_press:
  JSR WAIT_FRAME
  JSR READ_JOY
  LDA JOY
  AND #BTN_MASK
  BEQ .wf_press
  RTS


; ---------------------------------------------------------------
; NMI (vblank): scrive la Sprite Attribute Table e la coda dei tile.
; Il main loop scrive solo in RAM (SAT_BUFFER e coda Q*). Quando deve
; scrivere direttamente sul VDP (schermate) spegne l'interrupt con
; VDP_INT_OFF. Usa solo A e X.
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
  LDA QGO               ; tile in coda: name table
  BEQ .nt_end
  LDX #$00
.nt_q:
  LDA QLO,X
  STA VREG
  LDA QHI,X
  STA VREG
  LDA QTL,X
  STA VDATA
  INX
  CPX QGO
  BNE .nt_q
  LDA #$00
  STA QGO
.nt_end:
  PHY
  JSR SND_TICK            ; audio: effetti, musica e registri dei due AY
  PLY
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
  LDA FRAME_CNT           ; riallinea WAIT_FRAME
  STA LAST_FRAME
  LDA #$E6                ; R1: 16K + display ON + INT ON
  STA VREG
  LDA #(VDP_REGISTER_BITS | 1)
  STA VREG
  RTS

; SAT: 0 colpo, 1 cannone, 2 pulce, 3 ragno, 4 esplosione, 5 libero
SAT_BUFFER:    .byte HIDE_Y,$00,0,$0F    ; 0: colpo (bianco)
               .byte HIDE_Y,$00,4,$0B    ; 1: cannone (giallo)
               .byte HIDE_Y,$00,8,$07    ; 2: pulce (azzurro), nome 8/12
               .byte HIDE_Y,$00,16,$0D   ; 3: ragno (magenta), nome 16/20
               .byte HIDE_Y,$00,24,$08   ; 4: esplosione (rosso), nome 24/28/32
               .byte HIDE_Y,$00,0,$00    ; 5: libero
               .byte $D0                 ; 6: Y=$D0 = fine lista

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
DRAW_SPRITES:
  LDA BACT                     ; colpo
  BEQ .dr_nob
  LDA BY
  SEC
  SBC #1
  STA SAT_BUFFER
  LDA BX
  STA SAT_BUFFER+1
  BRA .dr_pl
.dr_nob:
  LDA #HIDE_Y
  STA SAT_BUFFER
.dr_pl:
  LDA DYING                    ; cannone
  BNE .dr_nop
  LDA PY
  SEC
  SBC #1
  STA SAT_BUFFER+4
  LDA PX
  STA SAT_BUFFER+5
  BRA .dr_fl
.dr_nop:
  LDA #HIDE_Y
  STA SAT_BUFFER+4
.dr_fl:
  LDA FACT                     ; pulce
  BEQ .dr_nof
  LDA FY
  SEC
  SBC #1
  STA SAT_BUFFER+8
  LDA FX
  STA SAT_BUFFER+9
  LDA FRAME_CNT
  AND #$08
  LSR A
  CLC
  ADC #8
  STA SAT_BUFFER+10
  BRA .dr_sp
.dr_nof:
  LDA #HIDE_Y
  STA SAT_BUFFER+8
.dr_sp:
  LDA SACT                     ; ragno
  BEQ .dr_nos
  LDA SY
  SEC
  SBC #1
  STA SAT_BUFFER+12
  LDA SX
  STA SAT_BUFFER+13
  LDA FRAME_CNT
  AND #$08
  LSR A
  CLC
  ADC #16
  STA SAT_BUFFER+14
  BRA .dr_ex
.dr_nos:
  LDA #HIDE_Y
  STA SAT_BUFFER+12
.dr_ex:
  LDA DYING                    ; esplosione del cannone
  BEQ .dr_noe
  LDA PY
  SEC
  SBC #5
  STA SAT_BUFFER+16
  LDA PX
  SEC
  SBC #4
  BCS .dr_ex2
  LDA #$00
.dr_ex2:
  STA SAT_BUFFER+17
  LDA DYING
  LSR A
  LSR A
  LSR A
  LSR A
  TAY
  LDA EXP_TAB,Y
  STA SAT_BUFFER+18
  RTS
.dr_noe:
  LDA #HIDE_Y
  STA SAT_BUFFER+16
  RTS

EXP_TAB:       .byte 24,28,32,32,28,24


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
   .byte $03,$76,$03,$01       ;R0: G2 | R1: 16K, 16x16 sprite | R2: name $3800 | R3: color $2000
                               ;R4: pattern $0000 | R5: SAT $3B00 | R6: sprite pattern $1800 | R7: sfondo nero


; ===============================================================
;  MOTORE AUDIO
;  Chip sinistro: A = effetto (tono), B = basso, C = effetto (rumore)
;  Chip destro:   A = melodia,        B = effetto (tono), C = effetto (rumore)
;  Il main loop chiede un effetto con SFX o un brano con PLAY_SONG;
;  SND_TICK (chiamato dall'NMI, 60 Hz) fa avanzare tutto e scrive gli AY.
; ===============================================================
SND_INIT:                      ; silenzio su entrambi i chip
  JSR SND_STOP
  LDX #10
.si_l:
  LDA #$00
  CPX #7
  BNE .si_v
  LDA #$3F                     ; mixer: tutto spento
.si_v:
  STX AY_L_LATCH
  STA AY_L_WRITE
  STX AY_R_LATCH
  STA AY_R_WRITE
  DEX
  BPL .si_l
  RTS

SND_STOP:                      ; ferma effetti e musica
  LDA #$00
  STA SFX_REQ
  STA SFX_CNT
  STA SFX_PRI
  STA MEL_ACT
  STA BAS_ACT
  STA MEL_VOL
  STA BAS_VOL
  STA MEL_NOTE
  STA BAS_NOTE
  STA MUS_ON
  RTS

; A = effetto (SFX_*). Si salva solo se non c'e' gia' una richiesta piu' importante.
SFX:
  PHX
  PHY
  TAX
  LDA SFX_PRI_TAB,X
  LDY SFX_REQ
  BEQ .sf_go
  CMP SFX_RPRI
  BCC .sf_end
.sf_go:
  STA SFX_RPRI
  INX
  STX SFX_REQ
.sf_end:
  PLY
  PLX
  RTS

; X = brano (SONG_*): parte la melodia sul chip destro e il basso sul sinistro
PLAY_SONG:
  TXA
  ASL A
  ASL A
  TAY
  LDA #$00
  STA MEL_ACT                  ; prima ferma le voci: l'NMI non le tocca mentre si imposta
  STA BAS_ACT
  LDA SONG_TAB,Y
  STA MEL_PTR
  LDA SONG_TAB+1,Y
  STA MEL_PTR+1
  LDA SONG_TAB+2,Y
  STA BAS_PTR
  LDA SONG_TAB+3,Y
  STA BAS_PTR+1
  LDA #$00
  STA MEL_CNT
  STA BAS_CNT
  STA MEL_VOL
  STA BAS_VOL
  LDA #$01
  STA MEL_ACT
  STA BAS_ACT
  STA MUS_ON
  RTS

; ---------------------------------------------------------------
; un frame di musica per la voce X (0 = melodia, 8 = basso)
; ---------------------------------------------------------------
MUS_VOICE:
  LDA MEL_ACT,X
  BEQ .mv_end
  LDA MEL_CNT,X
  BEQ .mv_fetch
  DEC MEL_CNT,X                ; nota in corso: il volume cala ogni 2 frame fino a 6
  LDA MEL_CNT,X
  AND #$01
  BNE .mv_end
  LDA MEL_VOL,X
  CMP #7
  BCC .mv_end
  DEC MEL_VOL,X
.mv_end:
  RTS
.mv_fetch:
  LDA (MEL_PTR,X)
  CMP #$FF
  BNE .mv_note
  LDA #$00                     ; fine brano
  STA MEL_ACT,X
  STA MEL_NOTE,X
  STA MEL_VOL,X
  RTS
.mv_note:
  STA MEL_NOTE,X
  INC MEL_PTR,X
  BNE .mv_p1
  INC MEL_PTR+1,X
.mv_p1:
  LDA (MEL_PTR,X)              ; durata in frame
  STA MEL_CNT,X
  DEC MEL_CNT,X
  INC MEL_PTR,X
  BNE .mv_p2
  INC MEL_PTR+1,X
.mv_p2:
  LDA MEL_NOTE,X
  BEQ .mv_rest
  ASL A
  TAY
  LDA NOTE_TAB-2,Y
  STA MEL_TPL,X
  LDA NOTE_TAB-1,Y
  STA MEL_TPH,X
  LDA #13                      ; attacco
  CPX #8
  BNE .mv_att
  LDA #11                      ; il basso e' un po' piu' piano
.mv_att:
  STA MEL_VOL,X
  RTS
.mv_rest:
  LDA #$00
  STA MEL_VOL,X
  RTS


; ---------------------------------------------------------------
; chiamato dall'NMI: usa A, X, Y
; ---------------------------------------------------------------
SND_TICK:
  LDA SFX_REQ                  ; --- nuovo effetto richiesto?
  BEQ .st_nr
  TAX
  DEX                          ; id
  LDA SFX_CNT
  BEQ .st_load
  LDA SFX_RPRI
  CMP SFX_PRI
  BCC .st_drop                 ; meno importante di quello in corso: scartato
.st_load:
  TXA
  ASL A
  STA NT0                      ; id * 2
  ASL A
  ASL A                        ; id * 8
  CLC
  ADC NT0                      ; id * 10
  TAY
  LDA SFX_TAB,Y
  STA SFX_MODE
  LDA SFX_TAB+1,Y
  STA SFX_PRI
  LDA SFX_TAB+2,Y
  STA SFX_CNT
  LDA SFX_TAB+3,Y
  STA SFX_PL
  LDA SFX_TAB+4,Y
  STA SFX_PH
  LDA SFX_TAB+5,Y
  STA SFX_DEL
  LDA SFX_TAB+6,Y
  STA SFX_VOL
  LDA SFX_TAB+7,Y
  STA SFX_DEC
  STA SFX_DCNT
  LDA SFX_TAB+8,Y
  STA SFX_NP
  LDA SFX_TAB+9,Y
  STA SFX_FLIP
  STA SFX_FCNT
  JMP .st_clr
.st_drop:
.st_clr:
  LDA #$00
  STA SFX_REQ
  JMP .st_music                ; il frame in cui parte l'effetto non lo fa avanzare
.st_nr:
  LDA SFX_CNT                  ; --- avanza l'effetto
  BEQ .st_music
  DEC SFX_CNT
  LDA SFX_DEL                  ; periodo += delta (con segno)
  BMI .st_neg
  CLC
  ADC SFX_PL
  STA SFX_PL
  BCC .st_pv
  INC SFX_PH
  BRA .st_pv
.st_neg:
  CLC
  ADC SFX_PL
  STA SFX_PL
  BCS .st_pv
  DEC SFX_PH
.st_pv:
  LDA SFX_PH
  BPL .st_pok
  LDA #$01                     ; mai sotto zero
  STA SFX_PL
  LDA #$00
  STA SFX_PH
.st_pok:
  LDA SFX_FLIP                 ; vibrato: inverte il delta
  BEQ .st_nf
  DEC SFX_FCNT
  BNE .st_nf
  LDA SFX_FLIP
  STA SFX_FCNT
  LDA SFX_DEL
  EOR #$FF
  CLC
  ADC #$01
  STA SFX_DEL
.st_nf:
  LDA SFX_DEC                  ; il volume cala
  BEQ .st_music
  DEC SFX_DCNT
  BNE .st_music
  LDA SFX_DEC
  STA SFX_DCNT
  LDA SFX_VOL
  BEQ .st_music
  DEC SFX_VOL
.st_music:
  LDX #0                       ; --- musica
  JSR MUS_VOICE
  LDX #8
  JSR MUS_VOICE
  LDA MEL_ACT
  ORA BAS_ACT
  STA MUS_ON
  ; --- volumi e mixer (0 = canale acceso)
  LDA #$00
  STA NT2                      ; volume effetto (tono)
  STA NT3                      ; volume effetto (rumore)
  LDA #$3F
  STA NT0                      ; mixer sinistro
  STA NT1                      ; mixer destro
  LDA SFX_CNT
  BEQ .st_nosfx
  LDA SFX_MODE
  AND #$01
  BEQ .st_nt
  LDA SFX_VOL
  STA NT2
  LDA NT0
  AND #$FE                     ; tono A (sx)
  STA NT0
  LDA NT1
  AND #$FD                     ; tono B (dx)
  STA NT1
.st_nt:
  LDA SFX_MODE
  AND #$02
  BEQ .st_nosfx
  LDA SFX_VOL
  STA NT3
  LDA NT0
  AND #$DF                     ; rumore su C (sx)
  STA NT0
  LDA NT1
  AND #$DF                     ; rumore su C (dx)
  STA NT1
.st_nosfx:
  LDA MEL_VOL
  BEQ .st_nom
  LDA NT1
  AND #$FE                     ; tono A (dx) = melodia
  STA NT1
.st_nom:
  LDA BAS_VOL
  BEQ .st_nob
  LDA NT0
  AND #$FD                     ; tono B (sx) = basso
  STA NT0
.st_nob:
  LDA SFX_PL                   ; --- registri 0,1,2,3,6,7,8,9,10 dei due chip
  STA LBUF
  STA RBUF+2
  LDA SFX_PH
  STA LBUF+1
  STA RBUF+3
  LDA BAS_TPL
  STA LBUF+2
  LDA BAS_TPH
  STA LBUF+3
  LDA MEL_TPL
  STA RBUF
  LDA MEL_TPH
  STA RBUF+1
  LDA SFX_NP
  STA LBUF+4
  STA RBUF+4
  LDA NT0
  STA LBUF+5
  LDA NT1
  STA RBUF+5
  LDA NT2
  STA LBUF+6                   ; vol A sx = effetto
  STA RBUF+7                   ; vol B dx = effetto
  LDA BAS_VOL
  STA LBUF+7                   ; vol B sx = basso
  LDA MEL_VOL
  STA RBUF+6                   ; vol A dx = melodia
  LDA NT3
  STA LBUF+8                   ; vol C = rumore
  STA RBUF+8
  LDY #8
.st_w:
  LDX AY_REGS,Y
  STX AY_L_LATCH
  LDA LBUF,Y
  STA AY_L_WRITE
  STX AY_R_LATCH
  LDA RBUF,Y
  STA AY_R_WRITE
  DEY
  BPL .st_w
  RTS

AY_REGS:       .byte 0,1,2,3,6,7,8,9,10


; ===============================================================
;  TABELLE (generate)
; ===============================================================
; blocchi da copiare nella VRAM: sorgente (2), lunghezza (2), indirizzo VRAM + bit di scrittura (2)
; (gli stessi tile e colori sono replicati nei 3 terzi dello schermo)
VDP_BLOCKS:
  .byte <PAT,>PAT,<(PAT_END-PAT),>(PAT_END-PAT),$00,$40
  .byte <PAT,>PAT,<(PAT_END-PAT),>(PAT_END-PAT),$00,$48
  .byte <PAT,>PAT,<(PAT_END-PAT),>(PAT_END-PAT),$00,$50
  .byte <VDP_SPRITE,>VDP_SPRITE,<(VDP_END_SPRITE-VDP_SPRITE),>(VDP_END_SPRITE-VDP_SPRITE),$00,$58
  .byte <COL,>COL,<(COL_END-COL),>(COL_END-COL),$00,$60
  .byte <COL,>COL,<(COL_END-COL),>(COL_END-COL),$00,$68
  .byte <COL,>COL,<(COL_END-COL),>(COL_END-COL),$00,$70

; sprite 16x16 (generatore sprite): proiettile, giocatore, pulce x2, ragno x2, esplosione x3
VDP_SPRITE:
  ; BULLET  (sprite name 0)
  .byte $18,$18,$18,$18,$18,$18,$18,$18,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  ; PLAYER  (sprite name 4)
  .byte $18,$18,$3C,$3C,$7E,$FF,$FF,$C3,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  ; FLEA_A  (sprite name 8)
  .byte $24,$18,$3C,$7E,$DB,$BD,$3C,$7E,$7E,$3C,$5A,$99,$24,$42,$81,$81
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  ; FLEA_B  (sprite name 12)
  .byte $A5,$3C,$3C,$7E,$DB,$BD,$3C,$7E,$7E,$3C,$99,$5A,$24,$24,$42,$81
  .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
  ; SPIDER_A  (sprite name 16)
  .byte $27,$5F,$B7,$3F,$4F,$97,$13,$21,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $E4,$FA,$ED,$FC,$F2,$E9,$C8,$84,$00,$00,$00,$00,$00,$00,$00,$00
  ; SPIDER_B  (sprite name 20)
  .byte $17,$2F,$5B,$BF,$1F,$AF,$8B,$05,$00,$00,$00,$00,$00,$00,$00,$00
  .byte $E8,$F4,$DA,$FD,$F8,$F5,$D1,$A0,$00,$00,$00,$00,$00,$00,$00,$00
  ; EXP_1  (sprite name 24)
  .byte $00,$00,$00,$02,$01,$0B,$07,$3F,$3F,$07,$0B,$01,$02,$00,$00,$00
  .byte $00,$00,$00,$40,$80,$D0,$E0,$FC,$FC,$E0,$D0,$80,$40,$00,$00,$00
  ; EXP_2  (sprite name 28)
  .byte $00,$21,$11,$0B,$C7,$6F,$3F,$FF,$FF,$3F,$6F,$C7,$0B,$11,$21,$00
  .byte $00,$84,$88,$D0,$E3,$F6,$FC,$FF,$FF,$FC,$F6,$E3,$D0,$88,$84,$00
  ; EXP_3  (sprite name 32)
  .byte $91,$49,$25,$92,$28,$C2,$08,$E0,$E0,$08,$C2,$28,$92,$25,$49,$91
  .byte $89,$92,$A4,$49,$14,$43,$10,$07,$07,$10,$43,$14,$49,$A4,$92,$89
VDP_END_SPRITE:

; pattern dei tile $00-$7F (replicati nei 3 terzi dello schermo)
PAT:
  .byte $00,$00,$00,$00,$00,$00,$00,$00   ; tile 00
  .byte $00,$00,$00,$00,$30,$18,$18,$3C
  .byte $00,$00,$38,$6E,$7E,$18,$18,$3C
  .byte $00,$7C,$DB,$FF,$7E,$18,$18,$3C
  .byte $3C,$7E,$DB,$FF,$7E,$18,$18,$3C
  .byte $3C,$7E,$FF,$FF,$FF,$FF,$7E,$5A
  .byte $3C,$7E,$FF,$FF,$FF,$FF,$7E,$A5
  .byte $3C,$7E,$FF,$FB,$FF,$FF,$7E,$BD
  .byte $3C,$7E,$FF,$DF,$FF,$FF,$7E,$BD
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $18,$18,$3C,$3C,$7E,$FF,$FF,$C3
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
  .byte $3F,$3F,$C0,$C0,$C0,$C0,$C0,$C0   ; tile 60
  .byte $00,$00,$C0,$C0,$00,$00,$00,$00
  .byte $C0,$C0,$C0,$C0,$3F,$3F,$00,$00
  .byte $00,$00,$C0,$C0,$00,$00,$00,$00
  .byte $FF,$FF,$C0,$C0,$C0,$C0,$FF,$FF
  .byte $C0,$C0,$00,$00,$00,$00,$00,$00
  .byte $C0,$C0,$C0,$C0,$FF,$FF,$00,$00
  .byte $00,$00,$00,$00,$C0,$C0,$00,$00
  .byte $C0,$C0,$C0,$C0,$F0,$F0,$CC,$CC
  .byte $C0,$C0,$C0,$C0,$C0,$C0,$C0,$C0
  .byte $C3,$C3,$C0,$C0,$C0,$C0,$00,$00
  .byte $C0,$C0,$C0,$C0,$C0,$C0,$00,$00
  .byte $FF,$FF,$0C,$0C,$0C,$0C,$0C,$0C
  .byte $C0,$C0,$00,$00,$00,$00,$00,$00
  .byte $0C,$0C,$0C,$0C,$0C,$0C,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $3F,$3F,$0C,$0C,$0C,$0C,$0C,$0C   ; tile 70
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $0C,$0C,$0C,$0C,$3F,$3F,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $FF,$FF,$C0,$C0,$C0,$C0,$FF,$FF
  .byte $00,$00,$C0,$C0,$C0,$C0,$00,$00
  .byte $C0,$C0,$C0,$C0,$C0,$C0,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $FF,$FF,$C0,$C0,$C0,$C0,$C0,$C0
  .byte $00,$00,$C0,$C0,$C0,$C0,$C0,$C0
  .byte $C0,$C0,$C0,$C0,$FF,$FF,$00,$00
  .byte $C0,$C0,$C0,$C0,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
  .byte $00,$00,$00,$00,$00,$00,$00,$00
PAT_END:

; colori dei tile $00-$7F (fg<<4 | bg, uno per riga)
COL:
  .byte $11,$11,$11,$11,$11,$11,$11,$11   ; tile 00
  .byte $91,$91,$91,$91,$91,$E1,$E1,$E1
  .byte $91,$91,$91,$91,$91,$E1,$E1,$E1
  .byte $91,$91,$91,$91,$91,$E1,$E1,$E1
  .byte $91,$91,$91,$91,$91,$E1,$E1,$E1
  .byte $31,$31,$31,$31,$31,$31,$31,$31
  .byte $31,$31,$31,$31,$31,$31,$31,$31
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $11,$11,$11,$11,$11,$11,$11,$11
  .byte $11,$11,$11,$11,$11,$11,$11,$11
  .byte $11,$11,$11,$11,$11,$11,$11,$11
  .byte $11,$11,$11,$11,$11,$11,$11,$11
  .byte $11,$11,$11,$11,$11,$11,$11,$11
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $11,$11,$11,$11,$11,$11,$11,$11
  .byte $11,$11,$11,$11,$11,$11,$11,$11   ; tile 10
  .byte $11,$11,$11,$11,$11,$11,$11,$11
  .byte $11,$11,$11,$11,$11,$11,$11,$11
  .byte $11,$11,$11,$11,$11,$11,$11,$11
  .byte $11,$11,$11,$11,$11,$11,$11,$11
  .byte $11,$11,$11,$11,$11,$11,$11,$11
  .byte $11,$11,$11,$11,$11,$11,$11,$11
  .byte $11,$11,$11,$11,$11,$11,$11,$11
  .byte $11,$11,$11,$11,$11,$11,$11,$11
  .byte $11,$11,$11,$11,$11,$11,$11,$11
  .byte $11,$11,$11,$11,$11,$11,$11,$11
  .byte $11,$11,$11,$11,$11,$11,$11,$11
  .byte $11,$11,$11,$11,$11,$11,$11,$11
  .byte $11,$11,$11,$11,$11,$11,$11,$11
  .byte $11,$11,$11,$11,$11,$11,$11,$11
  .byte $11,$11,$11,$11,$11,$11,$11,$11
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
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1   ; tile 60
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $91,$91,$91,$91,$91,$91,$91,$91
  .byte $91,$91,$91,$91,$91,$91,$91,$91
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $91,$91,$91,$91,$91,$91,$91,$91
  .byte $91,$91,$91,$91,$91,$91,$91,$91
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $91,$91,$91,$91,$91,$91,$91,$91
  .byte $91,$91,$91,$91,$91,$91,$91,$91
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $91,$91,$91,$91,$91,$91,$91,$91
  .byte $91,$91,$91,$91,$91,$91,$91,$91
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1   ; tile 70
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $91,$91,$91,$91,$91,$91,$91,$91
  .byte $91,$91,$91,$91,$91,$91,$91,$91
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $91,$91,$91,$91,$91,$91,$91,$91
  .byte $91,$91,$91,$91,$91,$91,$91,$91
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $B1,$B1,$B1,$B1,$B1,$B1,$B1,$B1
  .byte $91,$91,$91,$91,$91,$91,$91,$91
  .byte $91,$91,$91,$91,$91,$91,$91,$91
  .byte $11,$11,$11,$11,$11,$11,$11,$11
  .byte $11,$11,$11,$11,$11,$11,$11,$11
  .byte $11,$11,$11,$11,$11,$11,$11,$11
  .byte $11,$11,$11,$11,$11,$11,$11,$11
COL_END:

TITLE_REC:
  .byte 3, 7, 18, $60, $61, $64, $65, $68, $69, $6C, $6D, $70, $71, $74, $75, $64, $65, $78, $79, $64, $65   ; CENTIPEDE (alto)
  .byte 4, 7, 18, $62, $63, $66, $67, $6A, $6B, $6E, $6F, $72, $73, $76, $77, $66, $67, $7A, $7B, $66, $67   ; CENTIPEDE (basso)
  .byte 7, 9, 14, $4D, $49, $4E, $49, $56, $49, $43, $20, $41, $52, $43, $41, $44, $45   ; MINIVIC ARCADE
  .byte 10, 8, 15, $4A, $4F, $59, $53, $54, $49, $43, $4B, $20, $3D, $20, $4D, $4F, $56, $45   ; JOYSTICK = MOVE
  .byte 12, 8, 15, $42, $55, $54, $54, $4F, $4E, $20, $20, $20, $3D, $20, $46, $49, $52, $45   ; BUTTON   = FIRE
  .byte 14, 6, 21, $53, $45, $47, $4D, $45, $4E, $54, $20, $31, $30, $20, $20, $20, $48, $45, $41, $44, $20, $31, $30, $30   ; SEGMENT 10   HEAD 100
  .byte 16, 6, 24, $46, $4C, $45, $41, $20, $32, $30, $30, $20, $20, $53, $50, $49, $44, $45, $52, $20, $33, $30, $30, $2D, $39, $30, $30   ; FLEA 200  SPIDER 300-900
  .byte 18, 10, 8, $05, $06, $05, $06, $05, $06, $05, $07   ; centipede decorativo
  .byte 19, 6, 22, $00, $00, $04, $00, $00, $00, $00, $04, $00, $00, $00, $00, $00, $04, $00, $00, $00, $00, $00, $04, $00, $00   ; funghi
  .byte $FF

PRESS_REC:
  .byte 21, 9, 14, $50, $52, $45, $53, $53, $20, $41, $20, $42, $55, $54, $54, $4F, $4E   ; PRESS A BUTTON
  .byte $FF

OVER_REC:
  .byte 10, 9, 14, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00   ; cancella
  .byte 11, 11, 10, $47, $41, $4D, $45, $20, $20, $4F, $56, $45, $52   ; GAME  OVER
  .byte 12, 9, 14, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00   ; cancella
  .byte 13, 9, 14, $50, $52, $45, $53, $53, $20, $41, $20, $42, $55, $54, $54, $4F, $4E   ; PRESS A BUTTON
  .byte $FF

; riga 0 dello schermo di gioco (etichette fisse; le cifre vengono aggiornate dal gioco)
HUD_STATIC:
  .byte $00,$30,$30,$30,$30,$30,$30,$00,$00,$00,$00,$00,$00,$00,$00,$4C
  .byte $56,$00,$00,$00,$00,$48,$49,$00,$30,$30,$30,$30,$30,$30,$00,$00
; ===============================================================
;  AUDIO (2 x AY-3-8910, clock 1 MHz: periodo = 62500 / frequenza)
; ===============================================================
; note C2..B6 (indice 1-60): periodo del tono a 12 bit, lo/hi
NOTE_TAB:
  .byte $BC,$03,$86,$03,$53,$03,$24,$03,$F6,$02,$CC,$02,$A4,$02,$7E,$02,$5A,$02,$38,$02,$18,$02,$FA,$01
  .byte $DE,$01,$C3,$01,$AA,$01,$92,$01,$7B,$01,$66,$01,$52,$01,$3F,$01,$2D,$01,$1C,$01,$0C,$01,$FD,$00
  .byte $EF,$00,$E1,$00,$D5,$00,$C9,$00,$BE,$00,$B3,$00,$A9,$00,$9F,$00,$96,$00,$8E,$00,$86,$00,$7F,$00
  .byte $77,$00,$71,$00,$6A,$00,$64,$00,$5F,$00,$59,$00,$54,$00,$50,$00,$4B,$00,$47,$00,$43,$00,$3F,$00
  .byte $3C,$00,$38,$00,$35,$00,$32,$00,$2F,$00,$2D,$00,$2A,$00,$28,$00,$26,$00,$24,$00,$22,$00,$20,$00

; brani: (nota, durata in frame) ... $FF.  nota 0 = pausa
SONG_TITLE_MEL:
  .byte 34,8,37,8,41,8,46,8,41,8,37,8,34,8,29,8
  .byte 32,8,36,8,39,8,44,8,39,8,36,8,32,8,27,8
  .byte 30,8,34,8,37,8,42,8,41,8,39,8,37,8,36,8
  .byte 34,8,37,8,41,8,46,40,255
SONG_TITLE_BAS:
  .byte 10,16,17,16,10,16,17,16,8,16,15,16,8,16,15,16
  .byte 6,16,13,16,6,16,13,16,10,32,17,16,10,16,255
SONG_OVER_MEL:
  .byte 41,12,40,12,39,12,38,12,37,24,34,24,30,24,22,72
  .byte 255
SONG_OVER_BAS:
  .byte 22,48,18,48,15,48,10,24,10,72,255
SONG_LEVEL_MEL:
  .byte 37,5,41,5,44,5,49,5,53,8,56,24,255
SONG_LEVEL_BAS:
  .byte 13,12,20,12,25,28,255
SONG_LIFE_MEL:
  .byte 37,4,41,4,44,4,49,4,53,4,56,4,53,4,56,20
  .byte 255
SONG_LIFE_BAS:
  .byte 255

; indirizzi dei brani: melodia (2), basso (2)
SONG_TAB:
  .byte <SONG_TITLE_MEL,>SONG_TITLE_MEL,<SONG_TITLE_BAS,>SONG_TITLE_BAS
  .byte <SONG_OVER_MEL,>SONG_OVER_MEL,<SONG_OVER_BAS,>SONG_OVER_BAS
  .byte <SONG_LEVEL_MEL,>SONG_LEVEL_MEL,<SONG_LEVEL_BAS,>SONG_LEVEL_BAS
  .byte <SONG_LIFE_MEL,>SONG_LIFE_MEL,<SONG_LIFE_BAS,>SONG_LIFE_BAS

; effetti: modo, priorita, durata, periodo lo/hi, delta (con segno, per frame), volume,
;          ogni quanti frame cala il volume, periodo del rumore, ogni quanti frame inverte il delta
SFX_TAB:
  .byte 1,1,14,$28,$00,$05,13,2,0,0   ; SHOT0
  .byte 1,1,10,$B4,$00,$F4,12,2,0,0   ; SHOT1
  .byte 1,1,16,$46,$00,$06,12,3,0,2   ; SHOT2
  .byte 3,1,9,$1E,$00,$0A,12,1,6,0   ; SHOT3
  .byte 1,1,4,$40,$01,$00,10,1,0,0   ; HIT
  .byte 3,2,8,$04,$01,$19,13,1,14,0   ; POP
  .byte 3,2,12,$96,$00,$FA,14,1,10,0   ; BODY
  .byte 3,3,22,$90,$01,$F2,15,1,18,0   ; HEAD
  .byte 3,3,28,$28,$00,$09,14,1,8,0   ; FLEA
  .byte 3,3,36,$78,$00,$0A,14,2,12,3   ; SPIDER
  .byte 3,5,90,$B0,$04,$03,15,5,22,0   ; BOOM
  .byte 1,2,8,$64,$00,$0F,12,1,0,2   ; FLEAHIT
SFX_PRI_TAB:   .byte 1,1,1,1,1,2,2,3,3,3,5,2
