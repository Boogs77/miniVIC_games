;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;                                                              ;
;   miniVIC Z-MACHINE - story 1, joystick menus of words       ;
;   a Z-machine (version 3) interpreter for the miniVIC,       ;
;   written from the Z-Machine Standards Document 1.1          ;
;                                                              ;
;   - the story is read from the SD (sector 20480 + ...): the  ;
;     dynamic memory stays in RAM, the rest is paged in 512-byte ;
;     frames of RAM and of the free VRAM                       ;
;   - text mode 40 x 24 of the TMS9918A, font of the BIOS      ;
;   - needs the BIOS KEYB/SD (SD sectors, keyboard)            ;
;   - the story files are Zork I-III by Infocom, released under ;
;     the MIT License (c) 2025 Microsoft                       ;
;   - 3 saved games: zones 35, 44, 45 of the SD save area      ;
;                                                              ;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

SAVE_ZONE   = 35

; ---------------- hardware and BIOS KEYB/SD ----------------
VDP_DATA    = $B000
VDP_REG     = $B001
JOY1        = $D581    ; joystick 1 (active low)
JOY1_DDR    = $D583
KB_IFR      = $D18D    ; keyboard VIA: interrupt flags (bit 1 = CA1)
KB_IER      = $D18E    ;               interrupt enable
JT_CHRIN    = $FD03    ; C=1 and A = key, C=0 no key
JT_SHOW_MENU = $FD0F   ; back to the BIOS menu
JT_SD_READ  = $FD18    ; sector SD_LBA -> buffer X/Y, C=1 error
JT_SD_WRITE = $FD1B    ; buffer X/Y -> sector SD_LBA, C=1 error
JT_SD_INIT  = $FD1E    ; C=0 card ok
JT_KB_MODE  = $FD21    ; A<>0 extended keyboard
SD_LBA      = $0316    ; 4 bytes, sector number
IRQ_VEC     = $0FA0    ; JSR $0FA0 from the BIOS IRQ handler

; ---------------- SD layout ----------------
SD_AREA     = 20480    ; index of the stories; story k at SD_AREA + 1 + (k-1)*256
ST_SEC      = SD_AREA+1+(ST_NUM-1)*256
SAVE_SEC    = 32768+SAVE_ZONE*16+2   ; saved game: sectors 2-15 of the zone

; ---------------- memory ----------------
ZBASE       = (CODE_END+$FF)&$FF00   ; Z address 0: dynamic memory, then the RAM frames
                       ; (the font at CODE_END is in VRAM before the SD fills this)
MAXFR       = 24       ; RAM frames at most
NVF         = 26       ; VRAM frames ($0C00-$3FFF)
PMAP        = $0200    ; 256: page -> RAM high byte (0 = not in RAM)
VMAP        = $0500    ; 256: page -> VRAM frame + 1 (0 = not in VRAM)
ZSTACK      = $0600    ; Z stack (1 KB): words low byte first, call frames
ZSTACK_END  = $0A00
WORDBUF     = $0A00    ; 40: the word being printed
STATBUF     = $0A28    ; 40: text caught for the status line
LINEBUF     = $0A50    ; 40: a row of the screen while scrolling
EDBUF       = $0A80    ; 64: the line being typed
HIST        = $0AC0    ; 64: the line typed before (UP brings it back)
FOWN        = $0B00    ; 32: page in each RAM frame (0 = free)
FAGE        = $0B20    ; 32: clock of the last use of each frame (low byte)
VOWN        = $0B40    ; 32: page in each VRAM frame (0 = free)
SEPS        = $0B60    ; 16: word separators of the dictionary
ZCH         = $0B70    ; 6: z-characters of a word being encoded
ENC         = $0B78    ; 4: the word encoded
NUMBUF      = $0B7C    ; 6: digits of a number
KQ          = $0B80    ; 32: key queue (keyboard IRQ)
KQ_MASK     = $1F
FAGEH       = $0BA0    ; 32: clock of the last use (high byte)

; ---------------- zero page ($50-$FF; $00-$4F belong to the BIOS) ----------------
PC0         = $50      ; Z program counter, 17 bits
PC1         = $51
PC2         = $52
PCP         = $53      ; 2: RAM block of the PC (low byte always 0)
SA0         = $55      ; data stream address, 17 bits
SA1         = $56
SA2         = $57
SAP         = $58      ; 2: RAM block of SA (low byte always 0)
OPC         = $5A      ; opcode
NOPS        = $5B      ; number of operands
OPL         = $5C      ; 4: operands, low bytes
OPH         = $60      ; 4: operands, high bytes
ZSP         = $64      ; 2: Z stack pointer (next free byte)
FP          = $66      ; 2: first local of the routine
VAL         = $68      ; 2: value being moved
T0          = $6A
T1          = $6B
T2          = $6C
T3          = $6D
T4          = $6E
T5          = $6F
T6          = $70
T7          = $71
PTR         = $72      ; 2
PTR2        = $74      ; 2
GLOB0       = $76      ; 2: RAM address of global 0 - nothing: global n at GLOB0 + 2n (n < 128)
GLOB1       = $78      ; 2: GLOB0 + 256
PCF         = $7A      ; RAM frame of the PC ($FF = dynamic)
SAF         = $7B      ; RAM frame of SA
CLOCK       = $7C      ; use clock of the frames
RNG         = $7D      ; 2: random seed (xorshift)
OBJB        = $7F      ; 2: RAM address of object 0 (object n at OBJB + 9n)
OBJD        = $81      ; 2: RAM address of property default 0 (default n at OBJD + 2n)
ABBRP       = $83      ; 2: RAM address of the abbreviation table
ALPHA       = $85      ; text decoding: alphabet of the next character
ABBR        = $86      ;   abbreviation set waiting for its number (0 = none)
ESC         = $87      ;   ZSCII escape: 2 = high part next, 1 = low part next
ESCH        = $88      ;   high part of the escape
CURROW      = $89      ; screen: row and column of the cursor
CURCOL      = $8A
WLEN        = $8B      ; characters in WORDBUF
LINES       = $8C      ; lines printed since the last input
OUTMODE     = $8D      ; 0 screen, 1 into STATBUF
STLEN       = $8E      ; characters in STATBUF
DYNP        = $8F      ; pages of dynamic memory
FR0         = $90      ; high byte of RAM frame 0
NFR         = $91      ; RAM frames
VNEXT       = $92      ; next VRAM frame to fill
MPG         = $93      ; memory routines: page, frame, high byte, pointer
MFR         = $94
MHI         = $95
MPTR        = $96      ; 2
MT0         = $98
MT1         = $99
MSDB        = $9A      ; SD: RAM page of the buffer, tries
MSDT        = $9B
TXT         = $9C      ; 2: RAM address of the text buffer of READ
PARSE       = $9E      ; 2: RAM address of the parse buffer
KQR         = $A0      ; key queue: read index
KQW         = $A1      ;            write index
DICTB       = $A2      ; 2: Z address of the first dictionary entry
DICTL       = $A4      ; length of an entry
DICTN       = $A5      ; 2: entries
NSEP        = $A7      ; word separators
OT0         = $A8      ; object routines
OT1         = $A9
OT2         = $AA
HALT        = $AB      ; 1 = QUIT
SDCNT       = $AC      ; 2: sectors read (tests)
TOPROW      = $AE      ; first and last row of the text
BOTROW      = $AF
NLINES      = $B0      ; rows of text (MORE after NLINES-1)
INV         = $B1      ; $80 = print in inverse
KMAX        = $B2      ; READ: most characters
KLEN        = $B3      ;       characters typed
TT0         = $B4      ; text routines
TT1         = $B5
TT2         = $B6
TT3         = $B7
LO16        = $B8      ; 2: binary search: low, high, middle
HI16        = $BA      ; 2
MID16       = $BC      ; 2
ZCN         = $BE      ; z-characters in ZCH
ICNT        = $BF      ; 4: instructions run (tests)
SAV0        = $C3      ; save / restore: pointers and counters
SAV1        = $C4
SAV2        = $C5
SAV3        = $C6
SAVP        = $C7      ; 2
SAVQ        = $C9      ; 2
SAVN        = $CB      ; 2
CLKH        = $CD      ; use clock, high byte
MT2         = $CE
SCROLLS     = $CF      ; rows scrolled (READLINE follows its line)
; $D0-$FF: input module (keyboard or joystick)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;                                                              ;
;   START                                                      ;
;                                                              ;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

 .org $0FD0
  RTS                    ; NMI trampoline of the BIOS: the VDP interrupt stays off

 .org $1000
RESET:
  SEI
  CLD
  LDX #$FF
  TXS
  LDA #$60               ; RTS in the IRQ vector until the input module sets it
  STA IRQ_VEC
  JSR VDP_INIT           ; text mode, font, empty screen
  JSR BIOS_CHECK         ; the SD routines of the BIOS KEYB/SD
  JSR IN_INIT            ; keyboard or joystick
  JSR TITLE
  JSR SD_START           ; SD, story index
  JSR MEM_INIT           ; dynamic memory
  LDA #<MSG_READY
  LDY #>MSG_READY
  LDX #16
  JSR TITLE_LINE
  JSR IN_START           ; waits for a key / button 1; seeds RNG
  JSR VDP_CLEAR
  JSR Z_START
  JMP RUN

; BIOS_CHECK: without a JMP at $FD18, $FD1B and $FD1E (older BIOS) the
; title says so and the program stops: it cannot read the story
BIOS_CHECK:
  LDA #$4C
  CMP $FD18
  BNE .bc_no
  CMP $FD1B
  BNE .bc_no
  CMP $FD1E
  BNE .bc_no
  RTS
.bc_no:
  LDA #1
  STA TOPROW
  JSR TITLE
  LDA #<MSG_NOBIOS
  LDY #>MSG_NOBIOS
  LDX #16
  JSR TITLE_LINE
.bc_halt:
  BRA .bc_halt
MSG_NOBIOS: .byte "NEEDS THE BIOS KEYB/SD",0

; SD_START: card, index of the stories, release and serial of this story
SD_START:
  JSR JT_SD_INIT
  BCC .ss_ok
  LDA #<MSG_NOSD
  LDY #>MSG_NOSD
  JMP FATAL
.ss_ok:
  LDA #<SD_AREA
  STA SD_LBA
  LDA #>SD_AREA
  STA SD_LBA+1
  STZ SD_LBA+2
  STZ SD_LBA+3
  LDA #>ZBASE            ; the index goes where the dynamic memory will be
  JSR SD_READ
  LDX #3
.ss_sig:
  LDA ZBASE,X
  CMP SIG_ZSTO,X
  BNE .ss_bad
  DEX
  BPL .ss_sig
  LDA ZBASE+ST_NUM*16+2  ; release
  CMP #<ST_REL
  BNE .ss_bad
  LDA ZBASE+ST_NUM*16+3
  CMP #>ST_REL
  BNE .ss_bad
  LDX #5
.ss_ser:
  LDA ZBASE+ST_NUM*16+4,X
  CMP ST_SERIAL,X
  BNE .ss_bad
  DEX
  BPL .ss_ser
  RTS
.ss_bad:
  LDA #<MSG_NOSTORY
  LDY #>MSG_NOSTORY
  JMP FATAL
SIG_ZSTO:
  .byte "ZSTO"

; Z_START: header, globals, objects, dictionary, stack, PC (also RESTART)
Z_START:
  LDA ZBASE+1            ; flags 1: status line on, no split screen, fixed font
  AND #$8F
  STA ZBASE+1
  ; globals: global n (n = var - 16) at ZBASE + hdr[$0C] + 2n
  CLC
  LDA ZBASE+$0D
  STA GLOB0
  LDA ZBASE+$0C
  ADC #>ZBASE
  STA GLOB0+1
  LDA GLOB0
  STA GLOB1
  LDA GLOB0+1
  INC A
  STA GLOB1+1
  ; objects: defaults at hdr[$0A] (default n at OBJD + 2n: OBJD = table - 2)
  LDA ZBASE+$0B
  SEC
  SBC #2
  STA OBJD
  LDA ZBASE+$0A
  SBC #0
  CLC
  ADC #>ZBASE
  STA OBJD+1
  ; object n at table + 62 + 9(n-1) = table + 53 + 9n
  LDA ZBASE+$0B
  CLC
  ADC #53
  STA OBJB
  LDA ZBASE+$0A
  ADC #>ZBASE
  STA OBJB+1
  ; abbreviations
  LDA ZBASE+$19
  STA ABBRP
  LDA ZBASE+$18
  CLC
  ADC #>ZBASE
  STA ABBRP+1
  ; dictionary: separators, entry length, count, first entry
  LDA ZBASE+$09
  STA SA0
  LDA ZBASE+$08
  STA SA1
  STZ SA2
  JSR SA_LOAD
  JSR SA_BYTE
  STA NSEP
  LDX #0
.zs_sep:
  CPX NSEP
  BCS .zs_sepx
  JSR SA_BYTE
  CPX #16
  BCS .zs_skip
  STA SEPS,X
.zs_skip:
  INX
  BRA .zs_sep
.zs_sepx:
  JSR SA_BYTE
  STA DICTL
  JSR SA_BYTE
  STA DICTN+1
  JSR SA_BYTE
  STA DICTN
  LDA SA0
  STA DICTB
  LDA SA1
  STA DICTB+1
  LDA NSEP
  CMP #16
  BCC .zs_n
  LDA #16
  STA NSEP
.zs_n:
  ; stack, frame, PC
  LDA #<ZSTACK
  STA ZSP
  STA FP
  LDA #>ZSTACK
  STA ZSP+1
  STA FP+1
  LDA ZBASE+$07
  STA PC0
  LDA ZBASE+$06
  STA PC1
  STZ PC2
  JSR PC_LOAD
  STZ HALT
  STZ WLEN
  STZ LINES
  STZ OUTMODE
  LDA TOPROW
  STA CURROW
  STZ CURCOL
  RTS

; FATAL: message A/Y on the last row, then a key goes back to the BIOS menu
FATAL:
  PHA
  PHY
  JSR FLUSHW
  LDX BOTROW
  LDA #0
  JSR GOTOXY
  JSR CLEAR_ROW
  LDA #$80               ; in inverse
  STA INV
  PLY
  PLA
  JSR PUTSTR
  STZ INV
  JSR IN_WAIT
  JMP JT_SHOW_MENU

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;                                                              ;
;   INSTRUCTIONS                                               ;
;                                                              ;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

RUN:
  JSR STEP
  LDA HALT
  BEQ RUN
  JMP Z_QUIT

STEP:
  INC ICNT
  BNE .st_c
  INC ICNT+1
  BNE .st_c
  INC ICNT+2
.st_c:
  JSR FETCH
  STA OPC
  CMP #$80
  BCS .st_short
  ; long form: 2OP, bit 6 / bit 5 = operand 1 / 2 is a variable
  LDX #0
  AND #$40
  JSR .st_lt
  LDX #1
  LDA OPC
  AND #$20
  JSR .st_lt
  LDA #2
  STA NOPS
  LDA OPC
  AND #$1F
  ASL A
  TAX
  JMP (TAB2OP,X)
.st_lt:
  BEQ .st_lts
  LDA #2
  JMP RDOP
.st_lts:
  LDA #1
  JMP RDOP
.st_short:
  CMP #$C0
  BCS .st_var
  CMP #$B0
  BCS .st_0op
  ; 1OP: bits 5-4 = type
  LSR A
  LSR A
  LSR A
  LSR A
  AND #3
  LDX #0
  JSR RDOP
  LDA #1
  STA NOPS
  LDA OPC
  AND #$0F
  ASL A
  TAX
  JMP (TAB1OP,X)
.st_0op:
  STZ NOPS
  AND #$0F
  ASL A
  TAX
  JMP (TAB0OP,X)
.st_var:
  JSR FETCH              ; operand types
  STA T7
  LDX #0
.st_vl:
  LDA T7
  ROL A
  ROL A
  ROL A
  AND #3                 ; type of the next operand (bits 7-6)
  CMP #3
  BEQ .st_vx
  JSR RDOP
  ASL T7
  ASL T7
  INX
  CPX #4
  BCC .st_vl
.st_vx:
  STX NOPS
  LDA OPC
  AND #$1F
  ASL A
  TAX
  LDA OPC
  CMP #$E0
  BCS .st_vv
  JMP (TAB2OP,X)
.st_vv:
  JMP (TABVAR,X)

; RDOP: operand of type A (0 large, 1 small, 2 variable) into slot X. Keeps X
RDOP:
  CMP #1
  BEQ .ro_s
  BCS .ro_v
  JSR FETCH
  STA OPH,X
  JSR FETCH
  STA OPL,X
  RTS
.ro_s:
  JSR FETCH
  STA OPL,X
  STZ OPH,X
  RTS
.ro_v:
  JSR FETCH
  JSR GETVAR
  LDA VAL
  STA OPL,X
  LDA VAL+1
  STA OPH,X
  RTS

TAB2OP:
  .word OP_BAD, OP_JE, OP_JL, OP_JG, OP_DECCHK, OP_INCCHK, OP_JIN, OP_TEST
  .word OP_OR, OP_AND, OP_TESTATTR, OP_SETATTR, OP_CLRATTR, OP_STORE, OP_INSERT, OP_LOADW
  .word OP_LOADB, OP_GETPROP, OP_GETPROPA, OP_GETNEXT, OP_ADD, OP_SUB, OP_MUL, OP_DIV
  .word OP_MOD, OP_BAD, OP_BAD, OP_BAD, OP_BAD, OP_BAD, OP_BAD, OP_BAD
TAB1OP:
  .word OP_JZ, OP_GETSIB, OP_GETCHILD, OP_GETPARENT, OP_PROPLEN, OP_INC, OP_DEC, OP_PRINTADDR
  .word OP_BAD, OP_REMOVE, OP_PRINTOBJ, OP_RET, OP_JUMP, OP_PRINTPADDR, OP_LOAD, OP_NOT
TAB0OP:
  .word OP_RTRUE, OP_RFALSE, OP_PRINT, OP_PRINTRET, OP_NOP, OP_SAVE, OP_RESTORE, OP_RESTART
  .word OP_RETPOP, OP_POP, OP_QUIT, OP_NEWLINE, OP_SHOWSTATUS, OP_VERIFY, OP_BAD, OP_BAD
TABVAR:
  .word OP_CALL, OP_STOREW, OP_STOREB, OP_PUTPROP, OP_SREAD, OP_PRINTCHAR, OP_PRINTNUM, OP_RANDOM
  .word OP_PUSH, OP_PULL, OP_NOP, OP_NOP, OP_BAD, OP_BAD, OP_BAD, OP_BAD
  .word OP_BAD, OP_BAD, OP_BAD, OP_NOP, OP_NOP, OP_NOP, OP_BAD, OP_BAD
  .word OP_BAD, OP_BAD, OP_BAD, OP_BAD, OP_BAD, OP_BAD, OP_BAD, OP_BAD

OP_BAD:
  LDA #<MSG_BADOP
  LDY #>MSG_BADOP
  JMP FATAL

; ---------------- variables ----------------
; GETVAR: VAL = variable A (0 = pop). Keeps X
GETVAR:
  CMP #16
  BCS .gv_glob
  CMP #0
  BEQ POPVAL
  ASL A
  TAY
  DEY
  DEY
  LDA (FP),Y
  STA VAL
  INY
  LDA (FP),Y
  STA VAL+1
  RTS
.gv_glob:
  SBC #16                ; C = 1
  ASL A
  TAY
  BCS .gv_g1
  LDA (GLOB0),Y
  STA VAL+1
  INY
  LDA (GLOB0),Y
  STA VAL
  RTS
.gv_g1:
  LDA (GLOB1),Y
  STA VAL+1
  INY
  LDA (GLOB1),Y
  STA VAL
  RTS

; POPVAL: VAL = top of the stack, popped. Keeps X
POPVAL:
  LDA ZSP
  SEC
  SBC #2
  STA ZSP
  BCS .pv_1
  DEC ZSP+1
.pv_1:
  LDY #0
  LDA (ZSP),Y
  STA VAL
  INY
  LDA (ZSP),Y
  STA VAL+1
  RTS

; PUSHVAL: VAL onto the stack. Keeps X
PUSHVAL:
  LDY #0
  LDA VAL
  STA (ZSP),Y
  INY
  LDA VAL+1
  STA (ZSP),Y
  LDA ZSP
  CLC
  ADC #2
  STA ZSP
  BCC .pu_1
  INC ZSP+1
  LDA ZSP+1
  CMP #>ZSTACK_END
  BCS .pu_full
.pu_1:
  RTS
.pu_full:
  LDA #<MSG_STACK
  LDY #>MSG_STACK
  JMP FATAL

; SETVAR: variable A = VAL (0 = push). Keeps X
SETVAR:
  CMP #16
  BCS .sv_glob
  CMP #0
  BEQ PUSHVAL
  ASL A
  TAY
  DEY
  DEY
  LDA VAL
  STA (FP),Y
  INY
  LDA VAL+1
  STA (FP),Y
  RTS
.sv_glob:
  SBC #16
  ASL A
  TAY
  BCS .sv_g1
  LDA VAL+1
  STA (GLOB0),Y
  INY
  LDA VAL
  STA (GLOB0),Y
  RTS
.sv_g1:
  LDA VAL+1
  STA (GLOB1),Y
  INY
  LDA VAL
  STA (GLOB1),Y
  RTS

; PEEKVAR / POKEVAR: like GETVAR / SETVAR, but variable 0 is the top of the stack in place
PEEKVAR:
  CMP #0
  BEQ .pk_top
  JMP GETVAR
.pk_top:
  JSR STKTOP
  LDA (PTR),Y
  STA VAL
  INY
  LDA (PTR),Y
  STA VAL+1
  RTS
POKEVAR:
  CMP #0
  BEQ .po_top
  JMP SETVAR
.po_top:
  JSR STKTOP
  LDA VAL
  STA (PTR),Y
  INY
  LDA VAL+1
  STA (PTR),Y
  RTS
STKTOP:                  ; PTR = ZSP - 2, Y = 0
  LDA ZSP
  SEC
  SBC #2
  STA PTR
  LDA ZSP+1
  SBC #0
  STA PTR+1
  LDY #0
  RTS

; STOREV: the store byte of the instruction gets VAL
STOREV:
  JSR FETCH
  JMP SETVAR

; STORE_A: store A (high byte 0)
STORE_A:
  STA VAL
  STZ VAL+1
  BRA STOREV

; BRANCH: C = condition
BRANCH:
  ROR T7                 ; bit 7 = condition
  JSR FETCH
  STA T6
  EOR T7
  BMI BR_NO             ; branch on the other condition
  LDA T6
  AND #$40
  BEQ .br_long
  LDA T6
  AND #$3F
  STA T4
  STZ T5
  BRA .br_go
.br_long:
  LDA T6
  AND #$3F
  CMP #$20
  BCC .br_pos
  ORA #$C0               ; 14-bit negative offset
.br_pos:
  STA T5
  JSR FETCH
  STA T4
.br_go:
  LDA T5
  BNE .br_jump
  LDA T4
  CMP #2
  BCS .br_jump
  STA VAL                ; offset 0 / 1: return false / true
  STZ VAL+1
  JMP ZRET
.br_jump:
  LDA T4
  SEC
  SBC #2
  STA T4
  BCS PC_ADD
  DEC T5
  ; fall through
; PC_ADD: PC = PC + T4/T5 (signed)
PC_ADD:
  CLC
  LDA PC0
  ADC T4
  STA PC0
  LDA PC1
  ADC T5
  STA PC1
  LDA T5
  BPL .pa_p
  LDA #$FF
  BRA .pa_h
.pa_p:
  LDA #0
.pa_h:
  ADC PC2
  AND #1
  STA PC2
  JMP PC_LOAD
BR_NO:
  LDA T6
  AND #$40
  BNE BR_X
  JSR FETCH              ; second byte of the offset
BR_X:
  RTS

; ZRET: return VAL from the routine
ZRET:
  LDA FP                 ; the frame starts 6 bytes before the locals
  SEC
  SBC #6
  STA ZSP
  LDA FP+1
  SBC #0
  STA ZSP+1
  LDY #0
  LDA (ZSP),Y
  STA PC0
  INY
  LDA (ZSP),Y
  STA PC1
  INY
  LDA (ZSP),Y
  STA PC2
  INY
  LDA (ZSP),Y
  STA T0                 ; store variable
  INY
  LDA (ZSP),Y
  TAX
  INY
  LDA (ZSP),Y
  STA FP+1
  STX FP
  JSR PC_LOAD
  LDA T0
  JMP SETVAR

; ---------------- 2OP ----------------
OP_JE:
  LDX #1
.je_lp:
  LDA OPL
  CMP OPL,X
  BNE .je_nx
  LDA OPH
  CMP OPH,X
  BEQ .je_t
.je_nx:
  INX
  CPX NOPS
  BCC .je_lp
  CLC
  JMP BRANCH
.je_t:
  SEC
  JMP BRANCH

; SCMP: N = 1 if signed OP(X) < OP(Y index in T0)... compares operand 0 with operand 1
SLT01:                   ; C = operand 0 < operand 1 (signed)
  LDA OPL
  CMP OPL+1
  LDA OPH
  SBC OPH+1
  BVC .sl_1
  EOR #$80
.sl_1:
  ASL A                  ; C = sign = less
  RTS
OP_JL:
  JSR SLT01
  JMP BRANCH
OP_JG:
  LDA OPL+1
  CMP OPL
  LDA OPH+1
  SBC OPH
  BVC .jg_1
  EOR #$80
.jg_1:
  ASL A
  JMP BRANCH

OP_DECCHK:
  LDA OPL
  JSR PEEKVAR
  LDA VAL
  BNE .dc_1
  DEC VAL+1
.dc_1:
  DEC VAL
  LDA OPL
  JSR POKEVAR
  LDA VAL                ; VAL < operand 1 ?
  CMP OPL+1
  LDA VAL+1
  SBC OPH+1
  BVC .dc_2
  EOR #$80
.dc_2:
  ASL A
  JMP BRANCH

OP_INCCHK:
  LDA OPL
  JSR PEEKVAR
  INC VAL
  BNE .ic_1
  INC VAL+1
.ic_1:
  LDA OPL
  JSR POKEVAR
  LDA OPL+1              ; operand 1 < VAL ?
  CMP VAL
  LDA OPH+1
  SBC VAL+1
  BVC .ic_2
  EOR #$80
.ic_2:
  ASL A
  JMP BRANCH

OP_JIN:
  LDA OPL
  JSR OBJADDR
  LDY #4
  LDA (PTR),Y
  CMP OPL+1
  BEQ .jin_t
  CLC
  JMP BRANCH
.jin_t:
  SEC
  JMP BRANCH

OP_TEST:
  LDA OPL
  AND OPL+1
  CMP OPL+1
  BNE .te_f
  LDA OPH
  AND OPH+1
  CMP OPH+1
  BNE .te_f
  SEC
  JMP BRANCH
.te_f:
  CLC
  JMP BRANCH

OP_OR:
  LDA OPL
  ORA OPL+1
  STA VAL
  LDA OPH
  ORA OPH+1
  STA VAL+1
  JMP STOREV
OP_AND:
  LDA OPL
  AND OPL+1
  STA VAL
  LDA OPH
  AND OPH+1
  STA VAL+1
  JMP STOREV

OP_STORE:
  LDA OPL+1
  STA VAL
  LDA OPH+1
  STA VAL+1
  LDA OPL
  JMP POKEVAR

; ADDR2: VAL = operand 0 + 2 * operand 1 / ADDR1: operand 0 + operand 1
ADDR2:
  LDA OPL+1
  ASL A
  STA VAL
  LDA OPH+1
  ROL A
  STA VAL+1
  BRA ADDR_ADD
ADDR1:
  LDA OPL+1
  STA VAL
  LDA OPH+1
  STA VAL+1
ADDR_ADD:
  CLC
  LDA VAL
  ADC OPL
  STA VAL
  LDA VAL+1
  ADC OPH
  STA VAL+1
  RTS

OP_LOADW:
  JSR ADDR2
  JSR READW
  JMP STOREV
OP_LOADB:
  JSR ADDR1
  JSR READB
  JMP STOREV

OP_ADD:
  CLC
  LDA OPL
  ADC OPL+1
  STA VAL
  LDA OPH
  ADC OPH+1
  STA VAL+1
  JMP STOREV
OP_SUB:
  SEC
  LDA OPL
  SBC OPL+1
  STA VAL
  LDA OPH
  SBC OPH+1
  STA VAL+1
  JMP STOREV

OP_MUL:
  LDA OPL
  STA T0
  LDA OPH
  STA T1
  LDA OPL+1
  STA T2
  LDA OPH+1
  STA T3
  JSR MUL16
  LDA T4
  STA VAL
  LDA T5
  STA VAL+1
  JMP STOREV

; MUL16: T4/T5 = T0/T1 * T2/T3 (low 16 bits)
MUL16:
  STZ T4
  STZ T5
  LDX #16
.mu_lp:
  ASL T4
  ROL T5
  ASL T0
  ROL T1
  BCC .mu_nx
  CLC
  LDA T4
  ADC T2
  STA T4
  LDA T5
  ADC T3
  STA T5
.mu_nx:
  DEX
  BNE .mu_lp
  RTS

; DIV16: T0/T1 = T0/T1 / T2/T3, T4/T5 = remainder (unsigned)
DIV16:
  STZ T4
  STZ T5
  LDX #16
.dv_lp:
  ASL T0
  ROL T1
  ROL T4
  ROL T5
  LDA T4
  SEC
  SBC T2
  TAY
  LDA T5
  SBC T3
  BCC .dv_nx
  STA T5
  STY T4
  INC T0
.dv_nx:
  DEX
  BNE .dv_lp
  RTS

; SDIV: signed division of operand 0 by operand 1: T0/T1 quotient, T4/T5 remainder
SDIV:
  LDA OPL+1
  ORA OPH+1
  BNE .sd_ok
  LDA #<MSG_DIV0
  LDY #>MSG_DIV0
  JMP FATAL
.sd_ok:
  LDA OPH
  STA T6                 ; sign of the dividend
  EOR OPH+1
  STA T7                 ; sign of the quotient
  LDA OPL
  STA T0
  LDA OPH
  STA T1
  BPL .sd_a
  JSR NEG01
.sd_a:
  LDA OPL+1
  STA T2
  LDA OPH+1
  STA T3
  BPL .sd_b
  SEC
  LDA #0
  SBC T2
  STA T2
  LDA #0
  SBC T3
  STA T3
.sd_b:
  JSR DIV16
  BIT T7
  BPL .sd_c
  JSR NEG01
.sd_c:
  BIT T6
  BPL .sd_x
  SEC
  LDA #0
  SBC T4
  STA T4
  LDA #0
  SBC T5
  STA T5
.sd_x:
  RTS
NEG01:
  SEC
  LDA #0
  SBC T0
  STA T0
  LDA #0
  SBC T1
  STA T1
  RTS

OP_DIV:
  JSR SDIV
  LDA T0
  STA VAL
  LDA T1
  STA VAL+1
  JMP STOREV
OP_MOD:
  JSR SDIV
  LDA T4
  STA VAL
  LDA T5
  STA VAL+1
  JMP STOREV

; ---------------- 1OP ----------------
OP_JZ:
  LDA OPL
  ORA OPH
  CMP #1                 ; C = 1 if not zero
  BCC .jz_t
  CLC
  JMP BRANCH
.jz_t:
  SEC
  JMP BRANCH

OP_INC:
  LDA OPL
  JSR PEEKVAR
  INC VAL
  BNE .in_1
  INC VAL+1
.in_1:
  LDA OPL
  JMP POKEVAR
OP_DEC:
  LDA OPL
  JSR PEEKVAR
  LDA VAL
  BNE .de_1
  DEC VAL+1
.de_1:
  DEC VAL
  LDA OPL
  JMP POKEVAR

OP_PRINTADDR:
  LDA OPL
  STA SA0
  LDA OPH
  STA SA1
  STZ SA2
  JSR SA_LOAD
  JMP PRINT_SA
OP_PRINTPADDR:
  LDA OPL
  ASL A
  STA SA0
  LDA OPH
  ROL A
  STA SA1
  LDA #0
  ROL A
  STA SA2
  JSR SA_LOAD
  JMP PRINT_SA

OP_RET:
  LDA OPL
  STA VAL
  LDA OPH
  STA VAL+1
  JMP ZRET

OP_JUMP:
  LDA OPL
  SEC
  SBC #2
  STA T4
  LDA OPH
  SBC #0
  STA T5
  JMP PC_ADD

OP_LOAD:
  LDA OPL
  JSR PEEKVAR
  JMP STOREV

OP_NOT:
  LDA OPL
  EOR #$FF
  STA VAL
  LDA OPH
  EOR #$FF
  STA VAL+1
  JMP STOREV

; ---------------- 0OP ----------------
OP_RTRUE:
  LDA #1
  BRA RET_A
OP_RFALSE:
  LDA #0
RET_A:
  STA VAL
  STZ VAL+1
  JMP ZRET

OP_PRINT:
  JSR PC_TO_SA
  JSR PRINT_SA
  JMP SA_TO_PC
OP_PRINTRET:
  JSR PC_TO_SA
  JSR PRINT_SA
  JSR SA_TO_PC
  LDA #13
  JSR CHOUT
  BRA OP_RTRUE
PC_TO_SA:
  LDA PC0
  STA SA0
  LDA PC1
  STA SA1
  LDA PC2
  STA SA2
  JMP SA_LOAD
SA_TO_PC:
  LDA SA0
  STA PC0
  LDA SA1
  STA PC1
  LDA SA2
  STA PC2
  JMP PC_LOAD

OP_NOP:
  RTS

OP_RETPOP:
  JSR POPVAL
  JMP ZRET
OP_POP:
  JMP POPVAL

OP_QUIT:
  LDA #1
  STA HALT
  RTS

OP_NEWLINE:
  LDA #13
  JMP CHOUT

OP_SHOWSTATUS:
  JMP SHOW_STATUS

OP_RESTART:
  JSR FLUSHW
  JSR LOAD_DYN
  JSR Z_START
  JMP VDP_CLEAR

; VERIFY: sum of the story from $40, read sector by sector from the SD into the frame
; that RAM_SCRATCH gives (the cache keeps working)
OP_VERIFY:
  JSR RAM_SCRATCH        ; MHI = a free RAM block
  STZ T0                 ; sum
  STZ T1
  STZ T2                 ; page
  LDA #<ST_LEN           ; words left to add (length / 2), less the header
  SEC
  SBC #$20
  STA T4
  LDA #>ST_LEN
  SBC #0
  STA T5
  LDY #$40               ; first byte
.vf_pg:
  PHY
  LDA T2
  JSR SD_PAGE
  PLY
  LDA MHI
  STA PTR+1
  STZ PTR
  LDX #2
.vf_half:
.vf_b:
  CLC
  LDA (PTR),Y
  ADC T0
  STA T0
  BCC .vf_1
  INC T1
.vf_1:
  INY
  CLC
  LDA (PTR),Y
  ADC T0
  STA T0
  BCC .vf_2
  INC T1
.vf_2:
  LDA T4                 ; one word less
  BNE .vf_3
  DEC T5
.vf_3:
  DEC T4
  LDA T4
  ORA T5
  BEQ .vf_end
  INY
  BNE .vf_b
  INC PTR+1
  DEX
  BNE .vf_half
  INC T2
  LDY #0
  BRA .vf_pg
.vf_end:
  LDY MFR                ; the frame back to the cache
  LDA #0
  STA FOWN,Y
  LDA T0
  CMP #<ST_SUM
  BNE .vf_bad
  LDA T1
  CMP #>ST_SUM
  BNE .vf_bad
  SEC
  JMP BRANCH
.vf_bad:
  CLC
  JMP BRANCH

; RAM_SCRATCH: MHI = a RAM frame taken out of the cache (not PCF, not SAF) until its
; FOWN entry is set to 0 again; its page goes down into the VRAM
RAM_SCRATCH:
  JSR VICTIM
  STY MFR
  TYA
  ASL A
  ADC FR0
  STA MHI
  LDX FOWN,Y
  BEQ .rs_1
  STZ PMAP,X
  JSR SPILL
.rs_1:
  LDY MFR
  LDA #$FF               ; busy: not free, and just used
  STA FOWN,Y
  JMP TOUCH

; ---------------- VAR ----------------
OP_CALL:
  JSR FETCH
  STA T0                 ; store variable
  LDA OPL
  ORA OPH
  BNE .ca_go
  STZ VAL                ; routine 0: returns false
  STZ VAL+1
  LDA T0
  JMP SETVAR
.ca_go:
  ; frame: PC (3), store variable, FP (2)
  LDY #0
  LDA PC0
  STA (ZSP),Y
  INY
  LDA PC1
  STA (ZSP),Y
  INY
  LDA PC2
  STA (ZSP),Y
  INY
  LDA T0
  STA (ZSP),Y
  INY
  LDA FP
  STA (ZSP),Y
  INY
  LDA FP+1
  STA (ZSP),Y
  CLC
  LDA ZSP
  ADC #6
  STA ZSP
  STA FP
  LDA ZSP+1
  ADC #0
  STA ZSP+1
  STA FP+1
  ; PC = 2 * routine
  LDA OPL
  ASL A
  STA PC0
  LDA OPH
  ROL A
  STA PC1
  LDA #0
  ROL A
  STA PC2
  JSR PC_LOAD
  JSR FETCH
  STA T1                 ; locals
  LDX #1
.ca_loc:
  DEC T1
  BMI .ca_x
  JSR FETCH              ; default value (big endian)
  STA VAL+1
  JSR FETCH
  STA VAL
  CPX NOPS
  BCS .ca_def
  LDA OPL,X
  STA VAL
  LDA OPH,X
  STA VAL+1
.ca_def:
  JSR PUSHVAL
  INX
  BRA .ca_loc
.ca_x:
  RTS

; ZRAM: PTR = ZBASE + VAL (a Z address in the dynamic memory)
ZRAM:
  LDA VAL
  STA PTR
  LDA VAL+1
  CLC
  ADC #>ZBASE
  STA PTR+1
  RTS

OP_STOREW:
  JSR ADDR2
  JSR ZRAM
  LDY #0
  LDA OPH+2
  STA (PTR),Y
  INY
  LDA OPL+2
  STA (PTR),Y
  RTS
OP_STOREB:
  JSR ADDR1
  JSR ZRAM
  LDA OPL+2
  STA (PTR)
  RTS

OP_PRINTCHAR:
  LDA OPL
  JMP CHOUT

OP_PRINTNUM:
  LDA OPL
  STA VAL
  LDA OPH
  STA VAL+1
  JSR NUMSTR             ; NUMBUF, X = length
  LDY #0
.pn_lp:
  LDA NUMBUF,Y
  PHY
  PHX
  JSR CHOUT
  PLX
  PLY
  INY
  DEX
  BNE .pn_lp
  RTS

; RANDOM: n > 0: 1..n; n <= 0: new seed, result 0 (xorshift like ref.js)
OP_RANDOM:
  LDA OPH
  BMI .rn_seed
  ORA OPL
  BEQ .rn_time
  ; s ^= s << 7
  LDA RNG+1
  LSR A
  LDA RNG
  ROR A                  ; A = (s << 7) high byte ... (s >> 1) low part
  EOR RNG+1
  STA RNG+1
  LDA RNG
  LSR A                  ; nothing: (s << 7) low byte = s bit 0 -> bit 7
  LDA #0
  ROR A
  EOR RNG
  STA RNG
  ; s ^= s >> 9
  LDA RNG+1
  LSR A
  EOR RNG
  STA RNG
  ; s ^= s << 8
  LDA RNG
  EOR RNG+1
  STA RNG+1
  ; result = s % n + 1
  LDA RNG
  STA T0
  LDA RNG+1
  STA T1
  LDA OPL
  STA T2
  LDA OPH
  STA T3
  JSR DIV16
  CLC
  LDA T4
  ADC #1
  STA VAL
  LDA T5
  ADC #0
  STA VAL+1
  JMP STOREV
.rn_seed:
  SEC
  LDA #0
  SBC OPL
  STA RNG
  LDA #0
  SBC OPH
  STA RNG+1
  BRA .rn_0
.rn_time:
  LDA ICNT
  STA RNG
  LDA ICNT+1
  ORA #1
  STA RNG+1
.rn_0:
  LDA RNG
  ORA RNG+1
  BNE .rn_z
  INC RNG
.rn_z:
  LDA #0
  JMP STORE_A

OP_PUSH:
  LDA OPL
  STA VAL
  LDA OPH
  STA VAL+1
  JMP PUSHVAL
OP_PULL:
  JSR POPVAL
  LDA OPL
  JMP POKEVAR
; ===============================================================
;  MEMORY: dynamic pages in RAM, page cache in RAM and VRAM, SD
; ===============================================================
;
; A Z address has 17 bits (A2:A1:A0). A page is 512 bytes:
; page = A2:A1 >> 1, half = A1 bit 0, byte = A0.
; PMAP[page] = high byte of the RAM block holding half 0 of the
; page, 0 = not in RAM. The dynamic pages (0 .. DYNP-1) sit at
; ZBASE for good; the others come and go in the NFR frames that
; follow them (FR0 = high byte of frame 0). A page that leaves
; RAM goes down into one of the 26 frames of the free VRAM
; ($0C00-$3FFF); taken back from there, it frees its VRAM frame
; (the two caches hold different pages: 39-43 pages in all).
; The frame that leaves is the one used the longest time ago
; (16-bit use clock).
; Two streams read the memory: PC (the program counter) and SA
; (strings, tables, dictionary). Their frames are never taken.

; PAGE_GET: X = page -> A = high byte of half 0, Y = frame ($FF = dynamic)
PAGE_GET:
  LDA PMAP,X
  BEQ .pg_miss
  CMP FR0
  BCC .pg_dyn
  SBC FR0                ; C = 1
  LSR A
  TAY
  JSR TOUCH
  LDA PMAP,X
  RTS
.pg_dyn:
  LDY #$FF
  RTS
.pg_miss:
  JMP PAGE_LOAD

; PC_LOAD: PCP from PC0-PC2 (call after any change of PC1/PC2)
PC_LOAD:
  LDA PC2
  LSR A
  LDA PC1
  ROR A                  ; A = page, C = half
  PHP
  TAX
  JSR PAGE_GET
  STY PCF
  PLP
  ADC #0
  STA PCP+1
  RTS

; SA_LOAD: SAP from SA0-SA2
SA_LOAD:
  LDA SA2
  LSR A
  LDA SA1
  ROR A
  PHP
  TAX
  JSR PAGE_GET
  STY SAF
  PLP
  ADC #0
  STA SAP+1
  RTS

; FETCH: A = byte at PC, PC + 1. Keeps X (not Y)
FETCH:
  LDY PC0
  LDA (PCP),Y
  INC PC0
  BEQ .f_cross
  RTS
.f_cross:
  PHA
  INC PC1
  BNE .f_1
  INC PC2
.f_1:
  LDA PC1
  LSR A
  BCC .f_new
  INC PCP+1              ; second half of the same page
  PLA
  RTS
.f_new:
  PHX
  JSR PC_LOAD
  PLX
  PLA
  RTS

; SA_BYTE: A = byte at SA, SA + 1. Keeps X (not Y)
SA_BYTE:
  LDY SA0
  LDA (SAP),Y
  INC SA0
  BEQ .s_cross
  RTS
.s_cross:
  PHA
  INC SA1
  BNE .s_1
  INC SA2
.s_1:
  LDA SA1
  LSR A
  BCC .s_new
  INC SAP+1
  PLA
  RTS
.s_new:
  PHX
  JSR SA_LOAD
  PLX
  PLA
  RTS

; SA_SET: SA = VAL (16-bit byte address, bank 0), loaded
SA_SET:
  LDA VAL
  STA SA0
  LDA VAL+1
  STA SA1
  STZ SA2
  JMP SA_LOAD

; READW: VAL = word at Z address VAL (any memory)
READW:
  JSR SA_SET
  JSR SA_BYTE
  PHA
  JSR SA_BYTE
  STA VAL
  PLA
  STA VAL+1
  RTS

; READB: VAL = byte at Z address VAL
READB:
  JSR SA_SET
  JSR SA_BYTE
  STA VAL
  STZ VAL+1
  RTS

; TOUCH: frame Y used now
TOUCH:
  LDA CLOCK
  STA FAGE,Y
  LDA CLKH
  STA FAGEH,Y
  INC CLOCK
  BNE .to_x
  INC CLKH
.to_x:
  RTS

; VICTIM: Y = a free frame, or the one used the longest time ago (not PCF, not SAF)
VICTIM:
  STZ MT0                ; best age (16 bits)
  STZ MT2
  LDY #0
  STY MT1                ; best frame
.v_lp:
  CPY PCF
  BEQ .v_nx
  CPY SAF
  BEQ .v_nx
  LDA FOWN,Y
  BEQ .v_free
  LDA CLOCK
  SEC
  SBC FAGE,Y
  TAX
  LDA CLKH
  SBC FAGEH,Y
  CMP MT2
  BCC .v_nx
  BNE .v_best
  CPX MT0
  BCC .v_nx
.v_best:
  STX MT0
  STA MT2
  STY MT1
.v_nx:
  INY
  CPY NFR
  BCC .v_lp
  LDY MT1
  RTS
.v_free:
  RTS

; PAGE_LOAD: X = page not in RAM -> loads it; A = high byte, Y = frame
PAGE_LOAD:
  STX MPG
  JSR VICTIM
  STY MFR
  TYA
  ASL A
  ADC FR0
  STA MHI                ; high byte of the frame
  LDX FOWN,Y             ; the page that leaves (0 = free frame)
  BEQ .pl_free
  STZ PMAP,X
  JSR SPILL              ; down into the VRAM
.pl_free:
  LDX MPG
  LDA VMAP,X
  BEQ .pl_sd
  ; in VRAM: frame v-1 at $0C00 + (v-1)*$200; that VRAM frame is free again
  STZ VMAP,X
  DEC A
  TAY
  LDA #0
  STA VOWN,Y
  TYA
  ASL A
  ADC #$0C
  TAX
  LDA #0
  JSR VSETR
  LDA MHI
  JSR VR_TO_RAM
  BRA .pl_done
.pl_sd:
  LDA MPG
  JSR SD_PAGE            ; page -> RAM block MHI (512 bytes)
.pl_done:
  LDX MPG
  LDY MFR
  LDA MHI
  STA PMAP,X
  TXA
  STA FOWN,Y
  JSR TOUCH
  LDA MHI
  RTS

; SPILL: page X (in the RAM block MHI) into a VRAM frame: a free one, or the next in turn
SPILL:
  LDY #NVF-1
.sp_f:
  LDA VOWN,Y
  BEQ .sp_got
  DEY
  BPL .sp_f
  LDY VNEXT              ; none free: the next in turn leaves
  INC VNEXT
  LDA VNEXT
  CMP #NVF
  BCC .sp_n
  STZ VNEXT
.sp_n:
  LDA VOWN,Y
  PHX
  TAX
  STZ VMAP,X
  PLX
.sp_got:
  TXA
  STA VOWN,Y
  TYA
  INC A
  STA VMAP,X
  TYA
  ASL A
  ADC #$0C
  TAX
  LDA #0
  JSR VSETW
  LDA MHI
  JMP RAM_TO_VR

; VR_TO_RAM: 512 bytes from the VRAM (address already set for reading) to RAM page A
VR_TO_RAM:
  STA MPTR+1
  STZ MPTR
  LDX #2
.vr_lp:
  LDY #0
.vr_b:
  LDA VDP_DATA
  STA (MPTR),Y
  INY
  BNE .vr_b
  INC MPTR+1
  DEX
  BNE .vr_lp
  RTS

; RAM_TO_VR: 512 bytes from RAM page A to the VRAM (address already set for writing)
RAM_TO_VR:
  STA MPTR+1
  STZ MPTR
  LDX #2
.rv_lp:
  LDY #0
.rv_b:
  LDA (MPTR),Y
  STA VDP_DATA
  INY
  BNE .rv_b
  INC MPTR+1
  DEX
  BNE .rv_lp
  RTS

; VSETW / VSETR: VRAM address A (low), X (high) for writing / reading
VSETW:
  STA VDP_REG
  TXA
  ORA #$40
  STA VDP_REG
  RTS
VSETR:
  STA VDP_REG
  STX VDP_REG
  RTS

; ---------------- SD ----------------
; SD_PAGE: story page A -> RAM block MHI (2 halves). The story starts at
; sector ST_SEC (ST_SEC = SD_AREA + 1 + (story - 1) * 256)
SD_PAGE:
  CLC
  ADC #<ST_SEC
  STA SD_LBA
  LDA #>ST_SEC
  ADC #0
  STA SD_LBA+1
  STZ SD_LBA+2
  STZ SD_LBA+3
  LDA MHI
  ; fall through
; SD_READ: sector SD_LBA -> RAM page A (512 bytes); 3 tries, then a fatal error
SD_READ:
  STA MSDB
  LDA #3
  STA MSDT
.sd_try:
  SEI
  LDX #0
  LDY MSDB
  JSR JT_SD_READ
  BCC .sd_ok
  DEC MSDT
  BNE .sd_try
  LDA #<MSG_SDERR
  LDY #>MSG_SDERR
  JMP FATAL
.sd_ok:
  CLI
  INC SDCNT
  BNE .sd_x
  INC SDCNT+1
.sd_x:
  RTS

; MEM_INIT: page tables, dynamic pages from the SD
MEM_INIT:
  LDX #0
.mi_clr:
  STZ PMAP,X
  STZ VMAP,X
  INX
  BNE .mi_clr
  LDX #NVF-1
.mi_v:
  STZ VOWN,X
  DEX
  BPL .mi_v
  LDX #MAXFR-1
.mi_f:
  STZ FOWN,X
  STZ FAGE,X
  STZ FAGEH,X
  DEX
  BPL .mi_f
  STZ CLOCK
  STZ CLKH
  STZ VNEXT
  STZ PCP                ; low bytes of the block pointers: always 0
  STZ SAP                ; (RAM is not cleared at power-on)
  LDA #$FF
  STA PCF
  STA SAF
  ; DYNP = pages of dynamic memory, FR0 = first frame, NFR = frames up to $8000
  LDA #>(ST_DYN+511)
  LSR A
  STA DYNP
  ASL A
  CLC
  ADC #>ZBASE
  STA FR0
  LDA #$80
  SEC
  SBC FR0
  LSR A
  CMP #MAXFR
  BCC .mi_n
  LDA #MAXFR
.mi_n:
  STA NFR
  ; fall through
; LOAD_DYN: dynamic pages 0 .. DYNP-1 from the SD into ZBASE
LOAD_DYN:
  LDX #0
.ld_lp:
  TXA
  ASL A
  CLC
  ADC #>ZBASE
  STA PMAP,X
  STA MHI
  PHX
  TXA
  JSR SD_PAGE
  PLX
  INX
  CPX DYNP
  BCC .ld_lp
  RTS
; ===============================================================
;  OBJECTS AND PROPERTIES (version 3: 255 objects, 32 attributes)
; ===============================================================
; Object n: 9 bytes at OBJB + 9n: attributes (4), parent, sibling,
; child, property table (big endian). The objects and the
; properties are in the dynamic memory, so they are read in RAM.

; OBJADDR: PTR = address of object A
OBJADDR:
  STA OT0
  STZ OT1
  ASL A
  ROL OT1
  ASL A
  ROL OT1
  ASL A
  ROL OT1
  CLC
  ADC OT0
  BCC .oa_1
  INC OT1
.oa_1:
  CLC
  ADC OBJB
  STA PTR
  LDA OT1
  ADC OBJB+1
  STA PTR+1
  RTS

; ATTRPOS: PTR = object of operand 0, Y = attribute byte, A = mask
ATTRPOS:
  LDA OPL
  JSR OBJADDR
  LDA OPL+1
  LSR A
  LSR A
  LSR A
  TAY
  LDA OPL+1
  AND #7
  TAX
  LDA BITMASK,X
  RTS
BITMASK:
  .byte $80,$40,$20,$10,$08,$04,$02,$01

OP_TESTATTR:
  JSR ATTRPOS
  AND (PTR),Y
  CMP #1                 ; C = 1 if set
  JMP BRANCH
OP_SETATTR:
  JSR ATTRPOS
  ORA (PTR),Y
  STA (PTR),Y
  RTS
OP_CLRATTR:
  JSR ATTRPOS
  EOR #$FF
  AND (PTR),Y
  STA (PTR),Y
  RTS

; OBJLINK: A = byte Y (4 parent, 5 sibling, 6 child) of object operand 0
OBJLINK:
  PHY
  LDA OPL
  JSR OBJADDR
  PLY
  LDA (PTR),Y
  RTS

OP_GETPARENT:
  LDY #4
  JSR OBJLINK
  JMP STORE_A
OP_GETSIB:
  LDY #5
  BRA GETLINK_B
OP_GETCHILD:
  LDY #6
GETLINK_B:
  JSR OBJLINK
  PHA
  JSR STORE_A
  PLA
  CMP #1
  JMP BRANCH

; REMOVE: object A out of its parent
REMOVE:
  STA OT2
  JSR OBJADDR
  LDY #4
  LDA (PTR),Y
  BEQ .rm_x              ; no parent
  LDA PTR                ; PTR2 = the object
  STA PTR2
  LDA PTR+1
  STA PTR2+1
  LDA (PTR),Y
  JSR OBJADDR            ; PTR = parent
  LDY #6
  LDA (PTR),Y
  CMP OT2
  BNE .rm_walk
  LDY #5                 ; first child: the parent gets the sibling
  LDA (PTR2),Y
  LDY #6
  STA (PTR),Y
  BRA .rm_clear
.rm_walk:
  ; A = a child: look for the one whose sibling is the object
  JSR OBJADDR
  LDY #5
  LDA (PTR),Y
  BEQ .rm_clear          ; not found (broken tree)
  CMP OT2
  BNE .rm_walk
  LDA (PTR2),Y           ; Y = 5
  STA (PTR),Y
.rm_clear:
  LDA #0
  LDY #4
  STA (PTR2),Y
  INY
  STA (PTR2),Y
.rm_x:
  RTS

OP_REMOVE:
  LDA OPL
  JMP REMOVE

OP_INSERT:
  LDA OPL
  JSR REMOVE
  LDA OPL+1
  JSR OBJADDR            ; destination
  LDY #6
  LDA (PTR),Y
  STA OT2                ; its first child
  LDA OPL
  STA (PTR),Y            ; the object is the first child now
  LDA OPL
  JSR OBJADDR
  LDY #4
  LDA OPL+1
  STA (PTR),Y            ; parent
  INY
  LDA OT2
  STA (PTR),Y            ; sibling = the old first child
  RTS

; FIRSTPROP: PTR2 = size byte of the first property of object A
FIRSTPROP:
  JSR OBJADDR
  LDY #7
  LDA (PTR),Y
  CLC
  ADC #>ZBASE
  STA PTR2+1
  INY
  LDA (PTR),Y
  STA PTR2
  LDA (PTR2)             ; length of the name in words
  ASL A
  SEC                    ; + 1 for the length byte
  ADC PTR2
  STA PTR2
  BCC .fp_1
  INC PTR2+1
.fp_1:
  RTS

; NEXTPROP: PTR2 to the next property (from the size byte at PTR2)
NEXTPROP:
  LDA (PTR2)
  LSR A
  LSR A
  LSR A
  LSR A
  LSR A
  SEC
  ADC #1                 ; data length + 1 size byte
  CLC
  ADC PTR2
  STA PTR2
  BCC .np_1
  INC PTR2+1
.np_1:
  RTS

; FINDPROP: object operand 0, property operand 1 -> C = 1 found (PTR2 = size byte)
FINDPROP:
  LDA OPL
  JSR FIRSTPROP
.fd_lp:
  LDA (PTR2)
  BEQ .fd_no
  AND #$1F
  CMP OPL+1
  BEQ .fd_yes
  BCC .fd_no             ; in descending order: gone past it
  JSR NEXTPROP
  BRA .fd_lp
.fd_yes:
  SEC
  RTS
.fd_no:
  CLC
  RTS

OP_GETPROP:
  JSR FINDPROP
  BCC .gp_def
  LDA (PTR2)
  CMP #$20
  LDY #1
  BCS .gp_word
  LDA (PTR2),Y
  JMP STORE_A
.gp_word:
  LDA (PTR2),Y
  STA VAL+1
  INY
  LDA (PTR2),Y
  STA VAL
  JMP STOREV
.gp_def:
  LDA OPL+1
  ASL A
  TAY
  LDA (OBJD),Y
  STA VAL+1
  INY
  LDA (OBJD),Y
  STA VAL
  JMP STOREV

OP_GETPROPA:
  JSR FINDPROP
  BCC .ga_0
  LDA PTR2               ; Z address of the data = PTR2 + 1 - ZBASE
  CLC
  ADC #1
  STA VAL
  LDA PTR2+1
  ADC #0
  SEC
  SBC #>ZBASE
  STA VAL+1
  JMP STOREV
.ga_0:
  STZ VAL
  STZ VAL+1
  JMP STOREV

OP_GETNEXT:
  LDA OPL+1
  BNE .gn_find
  LDA OPL
  JSR FIRSTPROP
  BRA .gn_num
.gn_find:
  JSR FINDPROP
  BCS .gn_next
  LDA #<MSG_NOPROP
  LDY #>MSG_NOPROP
  JMP FATAL
.gn_next:
  JSR NEXTPROP
.gn_num:
  LDA (PTR2)
  AND #$1F
  JMP STORE_A

OP_PROPLEN:
  LDA OPL
  ORA OPH
  BEQ .pl_0
  LDA OPL                ; size byte at ZBASE + address - 1
  SEC
  SBC #1
  STA PTR
  LDA OPH
  SBC #0
  CLC
  ADC #>ZBASE
  STA PTR+1
  LDA (PTR)
  LSR A
  LSR A
  LSR A
  LSR A
  LSR A
  INC A
.pl_0:
  JMP STORE_A

OP_PUTPROP:
  JSR FINDPROP
  BCS .pp_ok
  LDA #<MSG_NOPROP
  LDY #>MSG_NOPROP
  JMP FATAL
.pp_ok:
  LDA (PTR2)
  CMP #$20
  LDY #1
  BCS .pp_word
  LDA OPL+2
  STA (PTR2),Y
  RTS
.pp_word:
  LDA OPH+2
  STA (PTR2),Y
  INY
  LDA OPL+2
  STA (PTR2),Y
  RTS

OP_PRINTOBJ:
  LDA OPL
; PRINTOBJ: short name of object A
PRINTOBJ:
  JSR OBJADDR
  LDY #7
  LDA (PTR),Y
  STA SA1
  INY
  LDA (PTR),Y
  CLC
  ADC #1                 ; the name follows its length byte
  STA SA0
  BCC .po_1
  INC SA1
.po_1:
  STZ SA2
  JSR SA_LOAD
  JMP PRINT_SA
; ===============================================================
;  TEXT: z-characters, words, screen, status line, READ
; ===============================================================
; Text mode 40 x 24: font at $0000 (128 characters + 128 inverse),
; name table at $0800. Row 0 = status line (inverse); text rows
; TOPROW..BOTROW scroll; the joystick menu has the rows below.

NAMET       = $0800

; VDP_INIT: text mode, font and its inverse, empty screen
VDP_INIT:
  LDX #0
.vi_r:
  LDA VDP_REGS,X
  STA VDP_REG
  TXA
  ORA #$80
  STA VDP_REG
  INX
  CPX #8
  BCC .vi_r
  LDA #0
  TAX
  JSR VSETW
  LDA #0                 ; font: 128 characters, then the same inverted
  JSR VI_FONT
  LDA #$FF
  JSR VI_FONT
  ; fall through
VDP_CLEAR:
  LDA #<NAMET
  LDX #>NAMET
  JSR VSETW
  LDX #4                 ; 1024 spaces (960 used)
  LDY #0
  LDA #32
.vc_lp:
  STA VDP_DATA
  INY
  BNE .vc_lp
  DEX
  BNE .vc_lp
  LDA TOPROW
  STA CURROW
  STZ CURCOL
  STZ LINES
  RTS
VI_FONT:                ; 1 KB of FONT, EOR A
  STA TT0
  LDA #<FONT
  STA PTR
  LDA #>FONT
  STA PTR+1
  LDX #4
  LDY #0
.vf_lp:
  LDA (PTR),Y
  EOR TT0
  STA VDP_DATA
  INY
  BNE .vf_lp
  INC PTR+1
  DEX
  BNE .vf_lp
  RTS
VDP_REGS:                ; text mode, 16 KB, display on, interrupt off; name $0800, font $0000
  .byte $00,$D0,$02,$00,$00,$00,$00,COLORS

; GOTOXY: cursor at row X, column A (VRAM address set for writing)
GOTOXY:
  STX CURROW
  STA CURCOL
  ; fall through
; SETPOS: VRAM address of the cursor, for writing
SETPOS:
  LDX CURROW
  LDA ROWLO,X
  CLC
  ADC CURCOL
  PHA
  LDA ROWHI,X
  ADC #0
  TAX
  PLA
  JMP VSETW

ROWLO:
  .byte <(NAMET+0),<(NAMET+40),<(NAMET+80),<(NAMET+120),<(NAMET+160),<(NAMET+200)
  .byte <(NAMET+240),<(NAMET+280),<(NAMET+320),<(NAMET+360),<(NAMET+400),<(NAMET+440)
  .byte <(NAMET+480),<(NAMET+520),<(NAMET+560),<(NAMET+600),<(NAMET+640),<(NAMET+680)
  .byte <(NAMET+720),<(NAMET+760),<(NAMET+800),<(NAMET+840),<(NAMET+880),<(NAMET+920)
ROWHI:
  .byte >(NAMET+0),>(NAMET+40),>(NAMET+80),>(NAMET+120),>(NAMET+160),>(NAMET+200)
  .byte >(NAMET+240),>(NAMET+280),>(NAMET+320),>(NAMET+360),>(NAMET+400),>(NAMET+440)
  .byte >(NAMET+480),>(NAMET+520),>(NAMET+560),>(NAMET+600),>(NAMET+640),>(NAMET+680)
  .byte >(NAMET+720),>(NAMET+760),>(NAMET+800),>(NAMET+840),>(NAMET+880),>(NAMET+920)

; PUTSTR: ASCII string A/Y (0 at the end) at the cursor, no wrapping (INV: $80 = inverse)
PUTSTR:
  STA PTR
  STY PTR+1
  JSR SETPOS
  LDY #0
.ps_lp:
  LDA (PTR),Y
  BEQ .ps_x
  ORA INV
  STA VDP_DATA
  INC CURCOL
  INY
  BRA .ps_lp
.ps_x:
  RTS

; TITLE_LINE: string A/Y centred on row X
TITLE_LINE:
  STA PTR
  STY PTR+1
  STX CURROW
  LDY #0
.tl_len:
  LDA (PTR),Y
  BEQ .tl_c
  INY
  BRA .tl_len
.tl_c:
  TYA
  EOR #$FF
  SEC
  ADC #40                ; 40 - length
  LSR A
  STA CURCOL
  JSR CLEAR_ROW
  LDA PTR
  LDY PTR+1
  JMP PUTSTR

; CLEAR_ROW: row CURROW with spaces (keeps CURCOL; PTR untouched)
CLEAR_ROW:
  LDA CURCOL
  PHA
  STZ CURCOL
  JSR SETPOS
  LDX #40
  LDA #32
.cr_lp:
  STA VDP_DATA
  DEX
  BNE .cr_lp
  PLA
  STA CURCOL
  RTS

; TITLE: name of the interpreter, the story, licence, credits
TITLE:
  LDA #<MSG_ZM
  LDY #>MSG_ZM
  LDX #2
  JSR TITLE_LINE
  LDA #<ST_TITLE
  LDY #>ST_TITLE
  LDX #5
  JSR TITLE_LINE
  LDA #<ST_SUB
  LDY #>ST_SUB
  LDX #6
  JSR TITLE_LINE
  LDA #<ST_COPY
  LDY #>ST_COPY
  LDX #9
  JSR TITLE_LINE
  LDA #<MSG_MIT
  LDY #>MSG_MIT
  LDX #10
  JSR TITLE_LINE
  LDA #<MSG_VERSION
  LDY #>MSG_VERSION
  LDX #13
  JSR TITLE_LINE
  JSR IN_HELP            ; the controls of the version
  LDA #<MSG_LOADING
  LDY #>MSG_LOADING
  LDX #16
  JSR TITLE_LINE
  LDA #<MSG_CREDITS
  LDY #>MSG_CREDITS
  LDX #23
  JMP TITLE_LINE

MSG_ZM:      .byte "miniVIC Z-MACHINE",0
MSG_MIT:     .byte "SOURCE: MIT LICENSE, 2025 MICROSOFT",0
MSG_LOADING: .byte "LOADING THE STORY FROM THE SD...",0
MSG_CREDITS: .byte "DEVELOPED BY BOOGS & CCAI",0
MSG_NOSTORY: .byte "STORY NOT FOUND ON THE SD",0
MSG_SDERR:   .byte "SD READ ERROR",0
MSG_BADOP:   .byte "ILLEGAL INSTRUCTION",0
MSG_STACK:   .byte "STACK FULL",0
MSG_DIV0:    .byte "DIVISION BY ZERO",0
MSG_NOPROP:  .byte "NO SUCH PROPERTY",0
MSG_MORE:    .byte "[MORE]",0

; Z_QUIT: the story has ended
Z_QUIT:
  JSR FLUSHW
  LDA #13
  JSR CHOUT
  LDA #$80
  STA INV
  LDA #<MSG_END
  LDY #>MSG_END
  JSR PUTSTR
  STZ INV
  JSR IN_WAIT
  JMP JT_SHOW_MENU

; ---------------- z-characters ----------------
; PRINT_SA: the string at SA, up to the word with bit 15 set
PRINT_SA:
  STZ ALPHA
  STZ ABBR
  STZ ESC
.pr_word:
  JSR SA_BYTE
  STA TT2                ; high byte
  JSR SA_BYTE
  STA TT3                ; low byte
  LDA TT2
  LSR A
  LSR A
  AND #$1F
  JSR ZCHAR
  LDA TT3                ; (high << 3 | low >> 5) & 31
  LSR A
  LSR A
  LSR A
  LSR A
  LSR A
  STA TT1
  LDA TT2
  ASL A
  ASL A
  ASL A
  ORA TT1
  AND #$1F
  JSR ZCHAR
  LDA TT3
  AND #$1F
  JSR ZCHAR
  LDA TT2
  BPL .pr_word
  RTS

; ZCHAR: one z-character A
ZCHAR:
  LDX ESC
  BEQ .zc_abbr
  CPX #2
  BNE .zc_esc2
  STA ESCH
  DEC ESC
  RTS
.zc_esc2:
  STZ ESC                ; ZSCII = ESCH << 5 | A
  STA TT0
  LDA ESCH
  ASL A
  ASL A
  ASL A
  ASL A
  ASL A
  ORA TT0
  JMP CHOUT
.zc_abbr:
  LDX ABBR
  BEQ .zc_plain
  JMP ABBREV
.zc_plain:
  CMP #6
  BCS .zc_char
  CMP #0
  BEQ .zc_space
  CMP #4
  BCS .zc_shift
  STA ABBR               ; 1-3: abbreviation, number next
  STZ ALPHA
  RTS
.zc_space:
  STZ ALPHA
  LDA #32
  JMP CHOUT
.zc_shift:
  SBC #3                 ; C = 1: 4 -> 1, 5 -> 2
  STA ALPHA
  RTS
.zc_char:
  LDX ALPHA
  STZ ALPHA
  CPX #1
  BEQ .zc_a1
  BCS .zc_a2
  ADC #$61-6             ; C = 0 here? (CMP #6 left C = 1)
  JMP CHOUT
.zc_a1:
  CLC
  ADC #$41-6
  JMP CHOUT
.zc_a2:
  CMP #6
  BNE .zc_a2c
  LDA #2                 ; ZSCII escape: two more z-characters
  STA ESC
  RTS
.zc_a2c:
  TAX
  LDA A2TAB-7,X
  JMP CHOUT
A2TAB:                   ; z-characters 7-31 of alphabet 2
  .byte 13,"0123456789.,!?_#'",34,47,92,45,58,40,41

; ABBREV: abbreviation 32 * (ABBR - 1) + A, printed in the middle of the string
ABBREV:
  STA TT0
  LDA ABBR
  DEC A
  ASL A
  ASL A
  ASL A
  ASL A
  ASL A
  ORA TT0                ; index 0-95
  STZ ABBR
  ASL A                  ; word offset (C = index >= 128)
  TAY
  LDA ABBRP+1
  ADC #0
  STA PTR+1
  LDA ABBRP
  STA PTR
  ; the string being decoded: SA and the low part of the word
  LDA SA0
  PHA
  LDA SA1
  PHA
  LDA SA2
  PHA
  LDA TT2
  PHA
  LDA TT3
  PHA
  LDA (PTR),Y            ; word address of the abbreviation (big endian), * 2
  STA TT1
  INY
  LDA (PTR),Y
  ASL A
  STA SA0
  LDA TT1
  ROL A
  STA SA1
  LDA #0
  ROL A
  STA SA2
  JSR SA_LOAD
  JSR PRINT_SA
  PLA
  STA TT3
  PLA
  STA TT2
  PLA
  STA SA2
  PLA
  STA SA1
  PLA
  STA SA0
  STZ ALPHA
  JMP SA_LOAD

; ---------------- output ----------------
; CHOUT: ZSCII character A (13 = new line), with word wrapping
CHOUT:
  LDX OUTMODE
  BNE .co_stat
  CMP #13
  BEQ .co_nl
  CMP #32
  BEQ .co_sp
  CMP #127
  BCS .co_q
  CMP #32
  BCS .co_ch
.co_q:
  LDA #'?'
.co_ch:
  LDX WLEN
  STA WORDBUF,X
  INX
  STX WLEN
  CPX #40
  BCS FLUSHW
  RTS
.co_sp:
  JSR FLUSHW
  LDA CURCOL
  CMP #40
  BCS .co_x
  LDA #32
  JMP PUTRAW
.co_nl:
  JSR FLUSHW
  JMP NEWLINE
.co_stat:
  LDX STLEN
  CPX #40
  BCS .co_x
  STA STATBUF,X
  INC STLEN
.co_x:
  RTS

; FLUSHW: the word in WORDBUF, on the next line if it does not fit
FLUSHW:
  LDA WLEN
  BEQ .fw_x
  CLC
  ADC CURCOL
  CMP #41
  BCC .fw_fit
  LDA CURCOL
  BEQ .fw_fit            ; longer than a line: cut by PUTRAW
  JSR NEWLINE
.fw_fit:
  LDX #0
.fw_lp:
  LDA WORDBUF,X
  PHX
  JSR PUTRAW
  PLX
  INX
  CPX WLEN
  BCC .fw_lp
  STZ WLEN
.fw_x:
  RTS

; PUTRAW: character A at the cursor (a new line first if the row is full)
PUTRAW:
  PHA
  LDA CURCOL
  CMP #40
  BCC .pr_ok
  JSR NEWLINE
.pr_ok:
  JSR SETPOS
  PLA
  ORA INV
  STA VDP_DATA
  INC CURCOL
  RTS

; NEWLINE: next row, scrolling at the bottom; [MORE] when a page is full
NEWLINE:
  STZ CURCOL
  LDA CURROW
  CMP BOTROW
  BCS .nl_scroll
  INC CURROW
  BRA .nl_more
.nl_scroll:
  JSR SCROLL
.nl_more:
  INC LINES
  LDA LINES
  CMP NLINES
  BCC .nl_x
  JSR MORE
.nl_x:
  RTS

; SCROLL: text rows up by one, the last one empty
SCROLL:
  INC SCROLLS
  LDX TOPROW
.sc_lp:
  CPX BOTROW
  BCS .sc_last
  PHX
  INX                    ; read row X+1
  LDA ROWLO,X
  PHA
  LDA ROWHI,X
  TAX
  PLA
  JSR VSETR
  LDY #0
.sc_rd:
  LDA VDP_DATA
  STA LINEBUF,Y
  INY
  CPY #40
  BCC .sc_rd
  PLX                    ; write row X
  PHX
  LDA ROWLO,X
  PHA
  LDA ROWHI,X
  TAX
  PLA
  JSR VSETW
  LDY #0
.sc_wr:
  LDA LINEBUF,Y
  STA VDP_DATA
  INY
  CPY #40
  BCC .sc_wr
  PLX
  INX
  BRA .sc_lp
.sc_last:
  LDA CURCOL
  PHA
  STZ CURCOL
  LDA BOTROW
  STA CURROW
  JSR CLEAR_ROW
  PLA
  STA CURCOL
  RTS

; MORE: [MORE] at the start of the row, waits, rubs it out
MORE:
  STZ LINES
  LDA CURCOL
  PHA
  STZ CURCOL
  LDA #$80
  STA INV
  LDA #<MSG_MORE
  LDY #>MSG_MORE
  JSR PUTSTR
  STZ INV
  JSR IN_WAIT
  STZ CURCOL
  JSR CLEAR_ROW
  PLA
  STA CURCOL
  RTS

; ---------------- numbers ----------------
; NUMSTR: VAL (signed) in decimal into NUMBUF, X = length
NUMSTR:
  LDX #0
  LDA VAL+1
  BPL .nu_pos
  LDA #'-'
  STA NUMBUF
  INX
  SEC
  LDA #0
  SBC VAL
  STA VAL
  LDA #0
  SBC VAL+1
  STA VAL+1
.nu_pos:
  STX TT1                ; where the digits start
  LDA VAL
  STA T0
  LDA VAL+1
  STA T1
  LDA #10
  STA T2
  STZ T3
  LDY #0                 ; digits, units first, on the 6502 stack
.nu_lp:
  PHY
  JSR DIV16
  PLY
  LDA T4
  ORA #'0'
  PHA
  INY
  LDA T0
  ORA T1
  BNE .nu_lp
  LDX TT1
.nu_out:
  PLA
  STA NUMBUF,X
  INX
  DEY
  BNE .nu_out
  RTS

; ---------------- status line ----------------
; SHOW_STATUS: row 0 in inverse: the room (global 0), score (global 1), moves (global 2)
SHOW_STATUS:
  JSR FLUSHW
  LDA CURROW
  PHA
  LDA CURCOL
  PHA
  LDA #1
  STA OUTMODE
  STZ STLEN
  LDA #16
  JSR GETVAR
  LDA VAL
  BEQ .ss_noname
  JSR PRINTOBJ
.ss_noname:
  STZ OUTMODE
  LDX #0
  STX CURROW
  STX CURCOL
  JSR SETPOS
  LDA #$80+32
  STA VDP_DATA
  LDX #0                 ; the name, 24 characters at most
.ss_name:
  CPX STLEN
  BCS .ss_pad
  CPX #24
  BCS .ss_pad
  LDA STATBUF,X
  ORA #$80
  STA VDP_DATA
  INX
  BRA .ss_name
.ss_pad:
  ; "S:nnn M:nnnn" at the right: build it in STATBUF
  STZ STLEN
  LDA #'S'
  JSR .ss_put
  LDA #':'
  JSR .ss_put
  LDA #17
  JSR .ss_num
  LDA #32
  JSR .ss_put
  LDA #'M'
  JSR .ss_put
  LDA #':'
  JSR .ss_put
  LDA #18
  JSR .ss_num
  ; spaces up to column 39 - STLEN, then the numbers, then a space
  TXA                    ; X = characters written after the first space (0-24)
  INC A
  STA TT0                ; column reached
.ss_sp:
  LDA STLEN
  CLC
  ADC TT0
  CMP #39
  BCS .ss_right
  LDA #$80+32
  STA VDP_DATA
  INC TT0
  BRA .ss_sp
.ss_right:
  LDX #0
.ss_r:
  LDA STATBUF,X
  ORA #$80
  STA VDP_DATA
  INX
  CPX STLEN
  BCC .ss_r
  LDA #$80+32
  STA VDP_DATA
  PLA
  STA CURCOL
  PLA
  STA CURROW
  RTS
.ss_put:
  PHX
  LDX STLEN
  STA STATBUF,X
  INC STLEN
  PLX
  RTS
.ss_num:
  PHX
  JSR GETVAR
  JSR NUMSTR
  LDY #0
.ss_nl:
  LDA NUMBUF,Y
  JSR .ss_put
  INY
  DEX
  BNE .ss_nl
  PLX
  RTS

; ---------------- READ ----------------
OP_SREAD:
  JSR FLUSHW
  JSR SHOW_STATUS
  STZ LINES
  LDA OPL                ; text buffer
  STA TXT
  LDA OPH
  CLC
  ADC #>ZBASE
  STA TXT+1
  LDA OPL+1              ; parse buffer
  STA PARSE
  LDA OPH+1
  CLC
  ADC #>ZBASE
  STA PARSE+1
  ; most characters: the buffer's less 1, 63 at most (EDBUF)
  LDA (TXT)
  DEC A
  CMP #63
  BCC .rd_max
  LDA #63
.rd_max:
  STA KMAX
  JSR READLINE           ; EDBUF, KLEN characters
  ; into the text buffer, in lower case, 0 at the end
  LDY #0
.rd_cp:
  CPY KLEN
  BCS .rd_end
  LDA EDBUF,Y
  CMP #'A'
  BCC .rd_lc
  CMP #'Z'+1
  BCS .rd_lc
  ORA #$20
.rd_lc:
  INY
  STA (TXT),Y
  BRA .rd_cp
.rd_end:
  INY
  LDA #0
  STA (TXT),Y
  STZ LINES
  ; fall through
; TOKENISE: the words of the text buffer into the parse buffer
TOKENISE:
  LDA #1
  STA TT0                ; position in the text buffer
  STZ TT3                ; words found
.tk_lp:
  LDY TT0
  LDA (TXT),Y
  BEQ .tk_end
  CMP #32
  BNE .tk_word
  INC TT0
  BRA .tk_lp
.tk_word:
  STY TT1                ; start
  JSR ISSEP
  BCC .tk_long
  INY                    ; a separator is a word of its own
  BRA .tk_got
.tk_long:
  INY
  LDA (TXT),Y
  BEQ .tk_got
  CMP #32
  BEQ .tk_got
  JSR ISSEP
  BCC .tk_long
.tk_got:
  STY TT0
  TYA
  SEC
  SBC TT1
  STA TT2                ; length
  LDA TT3
  LDY #0
  CMP (PARSE),Y          ; room in the parse buffer?
  BCS .tk_lp
  JSR ENCODE             ; ENC = the word TT1, TT2
  JSR LOOKUP             ; VAL = its dictionary entry or 0
  LDA TT3                ; entry 2 + 4n: address (big endian), length, start
  ASL A
  ASL A
  CLC
  ADC #2
  TAY
  LDA VAL+1
  STA (PARSE),Y
  INY
  LDA VAL
  STA (PARSE),Y
  INY
  LDA TT2
  STA (PARSE),Y
  INY
  LDA TT1
  STA (PARSE),Y
  INC TT3
  BRA .tk_lp
.tk_end:
  LDY #1
  LDA TT3
  STA (PARSE),Y
  RTS

; ISSEP: C = 1 if A is a word separator of the dictionary (keeps A, Y)
ISSEP:
  LDX NSEP
.is_lp:
  DEX
  BMI .is_no
  CMP SEPS,X
  BNE .is_lp
  SEC
  RTS
.is_no:
  CLC
  RTS

; ENCODE: the word of TT2 characters at TT1 in the text buffer -> ENC (6 z-characters)
ENCODE:
  STZ ZCN
  LDY TT1
  LDA TT2
  STA TT0+0              ; (TT0 is free here: the position is saved in the parse loop)
  PHY
.en_lp:
  PLY
  LDA TT0
  BEQ .en_pad
  DEC TT0
  LDA (TXT),Y
  INY
  PHY
  CMP #'a'
  BCC .en_a2
  CMP #'z'+1
  BCS .en_a2
  SEC
  SBC #$61-6
  JSR .en_put
  BRA .en_lp
.en_a2:
  LDX #A2LEN-1           ; in alphabet 2?
.en_f:
  CMP A2TAB,X
  BEQ .en_a2f
  DEX
  BPL .en_f
  ; ZSCII escape: 5, 6, high 5 bits, low 5 bits
  PHA
  LDA #5
  JSR .en_put
  LDA #6
  JSR .en_put
  PLA
  PHA
  LSR A
  LSR A
  LSR A
  LSR A
  LSR A
  JSR .en_put
  PLA
  AND #$1F
  JSR .en_put
  BRA .en_lp
.en_a2f:
  TXA                    ; z-character = position + 7 (.en_put changes X)
  CLC
  ADC #7
  PHA
  LDA #5
  JSR .en_put
  PLA
  JSR .en_put
  BRA .en_lp
.en_pad:
  LDA ZCN
  CMP #6
  BCS .en_pack
  LDA #5
  JSR .en_put
  BRA .en_pad
.en_pack:
  ; ENC = z0 z1 z2 | z3 z4 z5 with bit 15 on the second word
  LDA ZCH+0
  LDX ZCH+1
  LDY ZCH+2
  JSR .en_word
  STA ENC+1
  STX ENC
  LDA ZCH+3
  LDX ZCH+4
  LDY ZCH+5
  JSR .en_word
  STA ENC+3
  TXA
  ORA #$80
  STA ENC+2
  ; the restored position of the parse loop
  LDA TT1
  CLC
  ADC TT2
  STA TT0
  RTS
.en_put:
  LDX ZCN
  CPX #6
  BCS .en_px
  STA ZCH,X
  INC ZCN
.en_px:
  RTS
.en_word:                ; (A << 10) | (X << 5) | Y -> A low, X high
  STA TT0
  STY T6
  TXA
  ASL A
  ASL A
  ASL A
  ASL A
  ASL A                  ; low 3 bits of X in bits 7-5, C = bit 3
  ORA T6
  PHA
  TXA
  LSR A
  LSR A
  LSR A                  ; high 2 bits of X
  STA T6
  LDA TT0
  ASL A
  ASL A
  ORA T6
  TAX
  PLA
  RTS
A2LEN = 25

; LOOKUP: VAL = Z address of the dictionary entry equal to ENC, 0 = none (binary search)
LOOKUP:
  STZ LO16
  STZ LO16+1
  LDA DICTN
  SEC
  SBC #1
  STA HI16
  LDA DICTN+1
  SBC #0
  STA HI16+1
.lk_lp:
  ; while LO <= HI (signed)
  LDA HI16
  CMP LO16
  LDA HI16+1
  SBC LO16+1
  BVC .lk_v
  EOR #$80
.lk_v:
  BMI .lk_none
  ; MID = (LO + HI) / 2
  CLC
  LDA LO16
  ADC HI16
  STA MID16
  LDA LO16+1
  ADC HI16+1
  ROR A
  STA MID16+1
  ROR MID16
  ; address = DICTB + MID * DICTL (shift and add on the bits of DICTL)
  LDA MID16
  STA T0
  LDA MID16+1
  STA T1
  LDA DICTL
  STA T2
  STZ T4
  STZ T5
.lk_mul:
  LSR T2
  BCC .lk_m1
  CLC
  LDA T4
  ADC T0
  STA T4
  LDA T5
  ADC T1
  STA T5
.lk_m1:
  ASL T0
  ROL T1
  LDA T2
  BNE .lk_mul
  CLC
  LDA T4
  ADC DICTB
  STA VAL
  LDA T5
  ADC DICTB+1
  STA VAL+1
  JSR SA_SET
  LDX #0
.lk_cmp:
  JSR SA_BYTE
  CMP ENC,X
  BNE .lk_ne
  INX
  CPX #4
  BCC .lk_cmp
  RTS                    ; found: VAL = the entry
.lk_ne:
  BCC .lk_up             ; entry < word: LO = MID + 1
  LDA MID16              ; HI = MID - 1
  SEC
  SBC #1
  STA HI16
  LDA MID16+1
  SBC #0
  STA HI16+1
  BRA .lk_lp
.lk_up:
  LDA MID16
  CLC
  ADC #1
  STA LO16
  LDA MID16+1
  ADC #0
  STA LO16+1
  JMP .lk_lp
.lk_none:
  STZ VAL
  STZ VAL+1
  RTS
; ===============================================================
;  INPUT: JOYSTICK 1 - SENTENCES MADE OF WORDS FROM MENUS
; ===============================================================
; Rows 1-20: the story. Row 21: the sentence, row 22: the lists,
; row 23: the words of the list (the chosen one in inverse).
; UP/DOWN = list, LEFT/RIGHT = word (held: repeats), button 1 = adds
; the word (a direction or a game command on its own is sent at once),
; button 2 = sends the sentence. Button 2 held with UP = takes the last
; word away, DOWN = clears the sentence, LEFT/RIGHT = the words of the
; previous / next letter.
; Lists: GO, VERBS (of the story), HERE (nouns and adjectives on the
; screen, the newest first), WORDS (prepositions and the like), ALL
; (the whole dictionary), GAME (look, inventory, save ...).

COLORS      = $F4      ; white on dark blue
J_B1        = $10
J_B2        = $20
J_REP1      = 120      ; polls before a held direction repeats (~0.3 s)
J_REP2      = 30       ; then one word every 30 polls
EV_UP       = 1        ; events of JOY_EVENT
EV_DOWN     = 2
EV_LEFT     = 3
EV_RIGHT    = 4
EV_ADD      = 5
EV_SEND     = 6
EV_UNDO     = 7        ; button 2 + a direction: 6 + the direction
EV_CLEAR    = 8
EV_LPREV    = 9
EV_LNEXT    = 10
NCAT        = 6
C_GO        = 0        ; the lists
C_HERE      = 2
C_ALL       = 4
C_GAME      = 5
HMAX        = 48       ; words in HERE at most
ROW_SENT    = 21
ROW_CATS    = 22
ROW_WORDS   = 23

JPREV       = $D0      ; joystick state taken
JCAND       = $D1      ; a new state, and how many polls it lasted
JSTAB       = $D2
JUSED       = $D3      ; button 2 was used with a direction
JDIR        = $D4      ; event that repeats while held, 0 = none
JREP        = $D5      ; polls before the repeat
RNGC        = $D6      ; 2: counter while waiting (seeds RNG)
JCAT        = $D8      ; the list shown
JIDX        = $D9      ; 2: the word chosen in it
JN          = $DB      ; 2: words in the list
JI2         = $DD      ; 2: a word of the list (JGET, JFIRST)
KROW        = $DF      ; where the sentence goes in the story text
KCOL        = $E0
JWLEN       = $E1      ; length of JWBUF
JP          = $E2      ; 2: pointer
HCNT        = $E4      ; words in HERE
JCOL        = $E5
JT          = $E6
JKEY        = $E7
JROW        = $E8
JWS         = $E9      ; start of a word in LINEBUF
JWL         = $EA      ; its length
JSAVT       = $EB      ; 2: TXT while HERE is made
JDA         = $ED      ; 2: a dictionary entry
JSLOT       = $EF      ; slot of the cache

HDL         = $0C00    ; HERE: dictionary entry (low, high),
HDH         = $0C30    ;   VRAM address of the word on the screen (low, high),
HVL         = $0C60    ;   length
HVH         = $0C90
HLN         = $0CC0
JIL         = $0CF0    ; 8: the word chosen in each list (low, high)
JIH         = $0CF8
JWBUF       = $0D00    ; 24: a word of a list (0 at the end)
JCUR        = $0D18    ; 24: the word chosen (for the test pilot)
JEBUF       = $0D30    ; 16: a word of the screen, to look up
HCE0        = $0D40    ; cache of the words looked up (64, by a hash):
HCE1        = $0D80    ;   the encoded word (HCE0 = 0: empty slot),
HCE2        = $0DC0    ;   its dictionary entry if a noun or an adjective, else 0
HCE3        = $0E00
HCAL        = $0E40
HCAH        = $0E80

MSG_VERSION: .byte "JOYSTICK VERSION",0
MSG_READY:   .byte "PRESS A BUTTON TO BEGIN",0
MSG_NOSD:    .byte "NO SD CARD - PRESS A BUTTON",0
MSG_END:     .byte "[THE END - PRESS A BUTTON]",0

; IN_INIT: text rows 1-20, joystick in, keyboard interrupt off
IN_INIT:
  LDA #1
  STA TOPROW
  LDA #20
  STA BOTROW
  LDA #19
  STA NLINES
  STZ INV
  STZ JOY1_DDR
  LDA #$02               ; keyboard CA1 interrupt off
  STA KB_IER
  STZ JPREV
  STZ JCAND
  STZ JSTAB
  STZ JUSED
  STZ JDIR
  STZ JCAT
  STZ HCNT
  LDX #7
.ii_lp:
  STZ JIL,X
  STZ JIH,X
  DEX
  BPL .ii_lp
  LDX #63
.ii_hc:
  STZ HCE0,X
  DEX
  BPL .ii_hc
  RTS

; IN_HELP: the controls on the title screen
IN_HELP:
  LDA #<MSG_H1
  LDY #>MSG_H1
  LDX #18
  JSR TITLE_LINE
  LDA #<MSG_H2
  LDY #>MSG_H2
  LDX #19
  JSR TITLE_LINE
  LDA #<MSG_H3
  LDY #>MSG_H3
  LDX #20
  JSR TITLE_LINE
  LDA #<MSG_H4
  LDY #>MSG_H4
  LDX #21
  JMP TITLE_LINE
MSG_H1: .byte "UP/DOWN: LIST     LEFT/RIGHT: WORD",0
MSG_H2: .byte "BUTTON 1: ADD     BUTTON 2: SEND",0
MSG_H3: .byte "HOLD 2 + UP: UNDO   + DOWN: CLEAR",0
MSG_H4: .byte "HOLD 2 + LEFT/RIGHT: OTHER LETTER",0

; IN_START: a button at the title; the time it took seeds the random numbers
IN_START:
  JSR IN_WAIT
  LDA RNGC
  STA RNG
  LDA RNGC+1
  ORA #$40
  STA RNG+1
  RTS

; IN_WAIT: any button ([MORE], end, errors)
IN_WAIT:
  JSR JOY_EVENT
  CMP #EV_ADD
  BCC IN_WAIT
  RTS

; JDELAY: ~2.5 ms, counts RNGC
JDELAY:
  INC RNGC
  BNE .jd_1
  INC RNGC+1
.jd_1:
  LDY #2
.jd_o:
  LDX #0
.jd_i:
  DEX
  BNE .jd_i
  DEY
  BNE .jd_o
  RTS

; JOY_EVENT: A = the next event (waits). A new state counts after 3 equal polls
JOY_EVENT:
JE_LP:
  JSR JDELAY
JPOLL:                   ; (the test pilot sets the joystick here)
  LDA JOY1
  EOR #$FF
  AND #$3F
  CMP JPREV
  BNE .je_chg
  STZ JSTAB
  LDA JDIR               ; a direction held: it repeats
  BEQ JE_LP
  DEC JREP
  BNE JE_LP
  LDA #J_REP2
  STA JREP
  LDA JDIR
  RTS
.je_chg:
  CMP JCAND
  BEQ .je_c2
  STA JCAND
  STZ JSTAB
.je_c2:
  INC JSTAB
  LDA JSTAB
  CMP #3
  BCC JE_LP
  STZ JSTAB              ; JCAND is the new state
  STZ JDIR
  LDA JPREV
  EOR #$FF
  AND JCAND
  STA JT                 ; pressed now
  LDA JPREV
  LDX JCAND
  STX JPREV
  AND #J_B2              ; button 2 let go, used alone: send
  BEQ .je_n1
  TXA
  AND #J_B2
  BNE .je_n1
  LDA JUSED
  BNE JE_LP
  LDA #EV_SEND
  RTS
.je_n1:
  LDA JT
  AND #J_B2
  BEQ .je_n2
  STZ JUSED
.je_n2:
  LDA JT
  AND #$0F
  BEQ .je_b1
  LDX #EV_UP             ; the first direction pressed: 1-4
.je_dn:
  LSR A
  BCS .je_d
  INX
  BRA .je_dn
.je_d:
  LDA JPREV
  AND #J_B2
  BEQ .je_d2
  STA JUSED
  TXA
  CLC
  ADC #6
  TAX
.je_d2:
  TXA
  CMP #EV_LEFT           ; left, right and the letter jumps repeat
  BCC .je_x
  CMP #EV_ADD
  BCC .je_rep
  CMP #EV_LPREV
  BCC .je_x
.je_rep:
  STA JDIR
  LDX #J_REP1
  STX JREP
.je_x:
  RTS
.je_b1:
  LDA JT
  AND #J_B1
  BNE .je_b2
  JMP JE_LP
.je_b2:
  LDA JPREV              ; with button 2 held: no send when it is let go
  AND #J_B2
  STA JUSED
  LDA #EV_ADD
  RTS

; READLINE: the sentence into EDBUF (KLEN characters, KMAX at most), made
; from the menus; then written after the prompt in the story text
READLINE:
  STZ KLEN
  LDA CURROW
  STA KROW
  LDA CURCOL
  STA KCOL
  JSR HERE_SCAN
  STZ JIL+C_HERE         ; HERE: from its first word
  STZ JIH+C_HERE
  JSR JSETCAT
.rl_cats:
  JSR DRAW_CATS
.rl_draw:
  JSR DRAW_SENT
.rl_words:
  JSR DRAW_WORDS
.rl_ev:
  JSR JOY_EVENT
  ASL A
  TAX
  JMP (.rl_tab-2,X)
.rl_tab:
  .word .rl_up,.rl_down,.rl_left,.rl_right,.rl_add,.rl_send
  .word .rl_undo,.rl_clear,.rl_lprev,.rl_lnext
.rl_up:
  JSR JKEEP
  DEC JCAT
  BPL .rl_cat
  LDA #NCAT-1
  STA JCAT
  BRA .rl_cat
.rl_down:
  JSR JKEEP
  INC JCAT
  LDA JCAT
  CMP #NCAT
  BCC .rl_cat
  STZ JCAT
.rl_cat:
  JSR JSETCAT
  BRA .rl_cats
.rl_left:
  LDA JN
  ORA JN+1
  BEQ .rl_ev
  LDA JIDX
  ORA JIDX+1
  BNE .rl_l1
  LDA JN                 ; from the first word to the last
  STA JIDX
  LDA JN+1
  STA JIDX+1
.rl_l1:
  LDA JIDX
  BNE .rl_l2
  DEC JIDX+1
.rl_l2:
  DEC JIDX
  BRA .rl_words
.rl_right:
  LDA JN
  ORA JN+1
  BEQ .rl_ev
  INC JIDX
  BNE .rl_r1
  INC JIDX+1
.rl_r1:
  LDA JIDX
  CMP JN
  LDA JIDX+1
  SBC JN+1
  BCC .rl_words
  STZ JIDX               ; from the last word to the first
  STZ JIDX+1
  BRA .rl_words
.rl_add:
  JSR JADD
  BCS .rl_a1
  JMP .rl_ev             ; no word, or no room
.rl_a1:
  LDA JT                 ; the first word, from GO or GAME: sent at once
  BEQ .rl_a2
  LDA JCAT
  CMP #C_GO
  BEQ .rl_sd
  CMP #C_GAME
  BEQ .rl_sd
.rl_a2:
  JMP .rl_draw
.rl_send:
  LDA KLEN
  BNE .rl_sd
  JMP .rl_ev
.rl_sd:
  JSR JKEEP
  LDX #ROW_SENT          ; the sentence row is empty again
  LDA #0
  JSR GOTOXY
  JSR CLEAR_ROW
  LDA KROW               ; the sentence after the prompt
  STA CURROW
  LDA KCOL
  STA CURCOL
  STZ LINES
  LDX #0
.rl_echo:
  CPX KLEN
  BCS .rl_nl
  LDA EDBUF,X
  PHX
  JSR PUTRAW
  PLX
  INX
  BRA .rl_echo
.rl_nl:
  STZ LINES
  JMP NEWLINE
.rl_undo:                ; back to the space before the last word
  LDX KLEN
  BEQ .rl_un2
.rl_un1:
  DEX
  BEQ .rl_un2
  LDA EDBUF,X
  CMP #32
  BNE .rl_un1
.rl_un2:
  STX KLEN
  JMP .rl_draw
.rl_clear:
  STZ KLEN
  JMP .rl_draw
.rl_lnext:
  JSR JNEXTL
  JMP .rl_words
.rl_lprev:
  JSR JPREVL
  JMP .rl_words

; JADD: the chosen word at the end of the sentence (C=1 done; JT = 1 if it is the first)
JADD:
  LDA JN
  ORA JN+1
  BEQ .ja_no
  LDA JIDX
  STA JI2
  LDA JIDX+1
  STA JI2+1
  JSR JGET
  LDA KLEN               ; room: KLEN + space + word <= KMAX
  BEQ .ja_1
  INC A
.ja_1:
  CLC
  ADC JWLEN
  CMP KMAX
  BEQ .ja_ok
  BCS .ja_no
.ja_ok:
  STZ JT
  LDX KLEN
  BNE .ja_dg
  INC JT
  BRA .ja_cp
.ja_dg:                  ; a digit after a digit: the same number
  LDA JWBUF+1
  BNE .ja_sp
  LDA JWBUF
  JSR ISDIG
  BCC .ja_sp
  LDA EDBUF-1,X
  JSR ISDIG
  BCS .ja_cp
.ja_sp:
  LDA #32
  STA EDBUF,X
  INX
.ja_cp:
  LDY #0
.ja_lp:
  LDA JWBUF,Y
  BEQ .ja_x
  STA EDBUF,X
  INX
  INY
  BRA .ja_lp
.ja_x:
  STX KLEN
  SEC
  RTS
.ja_no:
  CLC
  RTS

; JKEEP: the word chosen in the list is kept for the next time
JKEEP:
  LDX JCAT
  LDA JIDX
  STA JIL,X
  LDA JIDX+1
  STA JIH,X
  RTS

; JSETCAT: JN = words of the list JCAT, JIDX = the one chosen there before
JSETCAT:
  LDX JCAT
  LDA JIL,X
  STA JIDX
  LDA JIH,X
  STA JIDX+1
  STZ JN+1
  CPX #C_HERE
  BNE .jc_1
  LDA HCNT
  STA JN
  BRA .jc_chk
.jc_1:
  CPX #C_ALL
  BNE .jc_2
  LDA DICTN
  STA JN
  LDA DICTN+1
  STA JN+1
  BRA .jc_chk
.jc_2:
  JSR JLIST              ; JP = the list
  LDX #0                 ; count the strings
  LDY #0
.jc_cnt:
  LDA (JP),Y
  BEQ .jc_cx
.jc_skip:
  INY
  BNE .jc_s1
  INC JP+1
.jc_s1:
  LDA (JP),Y
  BNE .jc_skip
  INX
  INY
  BNE .jc_cnt
  INC JP+1
  BRA .jc_cnt
.jc_cx:
  STX JN
.jc_chk:                 ; a word beyond the end: the first
  LDA JIDX
  CMP JN
  LDA JIDX+1
  SBC JN+1
  BCC .jc_x
  STZ JIDX
  STZ JIDX+1
.jc_x:
  RTS

; JLIST: JP = the word list of JCAT (GO, VERBS, WORDS, GAME)
JLIST:
  LDX JCAT
  LDA CAT_LO,X
  STA JP
  LDA CAT_HI,X
  STA JP+1
  RTS
CAT_LO: .byte <WL_GO,<WL_VERB,0,<WL_WORD,0,<WL_GAME
CAT_HI: .byte >WL_GO,>WL_VERB,0,>WL_WORD,0,>WL_GAME
CAT_NAME:
  .byte " GO ",0," VERBS ",0," HERE ",0," WORDS ",0," ALL ",0," GAME ",0

; JGET: word JI2 of the list JCAT -> JWBUF (0 at the end), JWLEN
JGET:
  LDA JCAT
  CMP #C_HERE
  BEQ .jg_here
  CMP #C_ALL
  BEQ .jg_all
  JSR JLIST
  LDX JI2                ; skip JI2 strings
  LDY #0
.jg_sk:
  CPX #0
  BEQ .jg_cp
.jg_s1:
  LDA (JP),Y
  INY
  BNE .jg_s2
  INC JP+1
.jg_s2:
  CMP #0
  BNE .jg_s1
  DEX
  BRA .jg_sk
.jg_cp:
  LDX #0
.jg_c1:
  LDA (JP),Y
  STA JWBUF,X
  BEQ .jg_x
  INX
  INY
  BNE .jg_c1
  INC JP+1
  BRA .jg_c1
.jg_x:
  STX JWLEN
  RTS
.jg_here:                ; from the screen, in lower case
  LDX JI2
  LDA HLN,X
  STA JWLEN
  LDA HVH,X
  PHA
  LDA HVL,X
  PLX
  JSR VSETR
  LDX #0
.jg_h1:
  CPX JWLEN
  BCS .jg_h2
  LDA VDP_DATA
  ORA #$20
  STA JWBUF,X
  INX
  BRA .jg_h1
.jg_h2:
  STZ JWBUF,X
  RTS
.jg_all:                 ; the dictionary entry, decoded
  JSR JENTRY
  JSR SA_SET
  LDA #1
  STA OUTMODE
  STZ STLEN
  JSR PRINT_SA
  STZ OUTMODE
  LDX #0
.jg_a1:
  CPX STLEN
  BCS .jg_a2
  LDA STATBUF,X
  STA JWBUF,X
  INX
  CPX #15
  BCC .jg_a1
.jg_a2:
  STZ JWBUF,X
  STX JWLEN
  RTS

; JENTRY: VAL = Z address of dictionary entry JI2
JENTRY:
  LDA JI2
  STA T0
  LDA JI2+1
  STA T1
  LDA DICTL
  STA T2
  STZ T3
  JSR MUL16
  CLC
  LDA T4
  ADC DICTB
  STA VAL
  LDA T5
  ADC DICTB+1
  STA VAL+1
  RTS

; JFIRST: A = the first letter of word JI2 (in ALL: its first z-character)
JFIRST:
  LDA JCAT
  CMP #C_ALL
  BEQ .jf_all
  JSR JGET
  LDA JWBUF
  RTS
.jf_all:
  JSR JENTRY
  JSR READB
  LDA VAL
  LSR A
  LSR A
  AND #$1F
  RTS

; JNEXTL: JIDX = the first word with another first letter (after the last: the first word)
JNEXTL:
  LDA JN
  ORA JN+1
  BEQ JN_X
  LDA JIDX
  STA JI2
  LDA JIDX+1
  STA JI2+1
  JSR JFIRST
  STA JKEY
.jn_lp:
  INC JI2
  BNE .jn_1
  INC JI2+1
.jn_1:
  LDA JI2
  CMP JN
  LDA JI2+1
  SBC JN+1
  BCS .jn_wrap
  JSR JFIRST
  CMP JKEY
  BEQ .jn_lp
  BRA JN_SET
.jn_wrap:
  STZ JI2
  STZ JI2+1
JN_SET:
  LDA JI2
  STA JIDX
  LDA JI2+1
  STA JIDX+1
JN_X:
  RTS

; JPREVL: JIDX = the first word of the letter before (from the first word: the last letter)
JPREVL:
  LDA JN
  ORA JN+1
  BEQ JN_X
  LDA JIDX               ; one word back
  STA JI2
  LDA JIDX+1
  STA JI2+1
  ORA JI2
  BNE .jp_1
  LDA JN
  STA JI2
  LDA JN+1
  STA JI2+1
.jp_1:
  JSR .jp_dec
  JSR JFIRST
  STA JKEY
.jp_lp:                  ; back while the word before has the same letter
  LDA JI2
  ORA JI2+1
  BEQ JN_SET
  JSR .jp_dec
  JSR JFIRST
  CMP JKEY
  BEQ .jp_lp
  INC JI2
  BNE JN_SET
  INC JI2+1
  BRA JN_SET
.jp_dec:
  LDA JI2
  BNE .jp_d1
  DEC JI2+1
.jp_d1:
  DEC JI2
  RTS

; DRAW_CATS: the names of the lists on row 22, the one shown in inverse
DRAW_CATS:
  LDX #ROW_CATS
  LDA #0
  JSR GOTOXY
  JSR CLEAR_ROW
  LDA #<CAT_NAME
  STA JP
  LDA #>CAT_NAME
  STA JP+1
  LDX #0
.dc_lp:
  PHX
  STZ INV
  CPX JCAT
  BNE .dc_1
  LDA #$80
  STA INV
.dc_1:
  LDA JP
  LDY JP+1
  JSR PUTSTR             ; (PUTSTR leaves Y = length)
  STZ INV
  INC CURCOL
  TYA
  SEC                    ; the 0 too
  ADC JP
  STA JP
  BCC .dc_2
  INC JP+1
.dc_2:
  PLX
  INX
  CPX #NCAT
  BCC .dc_lp
  RTS

; DRAW_SENT: "> " and the sentence (its end if long) on row 21, the cursor after it
DRAW_SENT:
  LDX #ROW_SENT
  LDA #0
  JSR GOTOXY
  JSR CLEAR_ROW
  JSR SETPOS
  LDA #'>'
  STA VDP_DATA
  LDA #32
  STA VDP_DATA
  LDX #0                 ; at most 37 characters: the last ones
  LDA KLEN
  SEC
  SBC #37
  BCC .ds_lp
  TAX
.ds_lp:
  CPX KLEN
  BCS .ds_cur
  LDA EDBUF,X
  STA VDP_DATA
  INX
  BRA .ds_lp
.ds_cur:
  LDA #$80+32
  STA VDP_DATA
  RTS

; DRAW_WORDS: row 23: "<", the chosen word in inverse, the next ones, ">"
DRAW_WORDS:
  LDX #ROW_WORDS
  LDA #0
  JSR GOTOXY
  JSR CLEAR_ROW
  STZ JCUR
  LDA JN
  ORA JN+1
  BNE .dw_some
  LDA #1
  STA CURCOL
  LDA #<MSG_NONE
  LDY #>MSG_NONE
  JMP PUTSTR
.dw_some:
  LDA JIDX
  STA JI2
  LDA JIDX+1
  STA JI2+1
  ORA JIDX
  BEQ .dw_0
  JSR SETPOS
  LDA #'<'
  STA VDP_DATA
.dw_0:
  LDA #1
  STA JCOL
  LDA #$80
  STA INV
.dw_lp:
  JSR JGET
  LDA INV                ; the chosen word, for the pilot
  BEQ .dw_1
  LDX #0
.dw_c:
  LDA JWBUF,X
  STA JCUR,X
  INX
  CPX #24
  BCC .dw_c
  BRA .dw_put
.dw_1:
  LDA JCOL               ; does it fit before column 39?
  CLC
  ADC JWLEN
  CMP #39
  BCS .dw_more
.dw_put:
  LDA JCOL
  STA CURCOL
  LDA #<JWBUF
  LDY #>JWBUF
  JSR PUTSTR
  STZ INV
  LDA CURCOL
  INC A
  STA JCOL
  INC JI2
  BNE .dw_2
  INC JI2+1
.dw_2:
  LDA JI2
  CMP JN
  LDA JI2+1
  SBC JN+1
  BCC .dw_lp
  RTS
.dw_more:
  LDA #39
  STA CURCOL
  JSR SETPOS
  LDA #'>'
  STA VDP_DATA
  RTS
MSG_NONE: .byte "(NOTHING)",0

; HERE_SCAN: the nouns and adjectives of the dictionary on rows 1-20,
; from the bottom row up, each once
HERE_SCAN:
  STZ HCNT
  LDA TXT
  STA JSAVT
  LDA TXT+1
  STA JSAVT+1
  LDA #<JEBUF            ; ENCODE reads the word from JEBUF
  STA TXT
  LDA #>JEBUF
  STA TXT+1
  LDA BOTROW
  STA JROW
.hs_row:
  LDX JROW               ; the row into LINEBUF
  LDA ROWHI,X
  PHA
  LDA ROWLO,X
  PLX
  JSR VSETR
  LDY #0
.hs_rd:
  LDA VDP_DATA
  STA LINEBUF,Y
  INY
  CPY #40
  BCC .hs_rd
  LDY #0
.hs_ch:
  CPY #40
  BCS .hs_next
  LDA LINEBUF,Y
  JSR ISLET
  BCS .hs_word
  INY
  BRA .hs_ch
.hs_word:
  STY JWS
  LDX #0
.hs_w1:
  CPX #9                 ; 9 letters are enough for the dictionary
  BCS .hs_w2
  STA JEBUF,X
  INX
.hs_w2:
  INY
  CPY #40
  BCS .hs_w3
  LDA LINEBUF,Y
  JSR ISLET
  BCS .hs_w1
.hs_w3:
  STX TT2
  TYA
  SEC
  SBC JWS
  STA JWL
  PHY
  JSR HERE_ADD
  PLY
  BRA .hs_ch
.hs_next:
  DEC JROW
  LDA JROW
  CMP TOPROW
  BCS .hs_row
  LDA JSAVT
  STA TXT
  LDA JSAVT+1
  STA TXT+1
  RTS

; HERE_ADD: the word of JEBUF (TT2 letters; JWL long at JWS of row JROW)
; into HERE if it is a noun or an adjective not there yet
HERE_ADD:
  LDA HCNT
  CMP #HMAX
  BCS .ha_end
  LDA JWL                ; 1-2 letters: not worth it
  CMP #3
  BCS .ha_go
.ha_end:
  RTS
.ha_go:
  STZ TT1
  JSR ENCODE
  LDA ENC                ; in the cache?
  CLC
  ADC ENC+1
  ADC ENC+2
  ADC ENC+3
  AND #63
  TAX
  LDA HCE0,X
  CMP ENC
  BNE .ha_miss
  LDA HCE1,X
  CMP ENC+1
  BNE .ha_miss
  LDA HCE2,X
  CMP ENC+2
  BNE .ha_miss
  LDA HCE3,X
  CMP ENC+3
  BNE .ha_miss
  LDA HCAL,X
  STA JDA
  LDA HCAH,X
  STA JDA+1
  BRA .ha_got
.ha_miss:
  STX JSLOT
  JSR LOOKUP
  STZ JDA
  STZ JDA+1
  LDA VAL
  ORA VAL+1
  BEQ .ha_put
  LDA VAL
  PHA
  CLC                    ; flags: $80 noun, $20 adjective
  ADC #4
  STA VAL
  LDA VAL+1
  PHA
  ADC #0
  STA VAL+1
  JSR READB
  PLY
  PLX
  LDA VAL
  AND #$A0
  BEQ .ha_put
  STX JDA
  STY JDA+1
.ha_put:
  LDX JSLOT
  LDA ENC
  STA HCE0,X
  LDA ENC+1
  STA HCE1,X
  LDA ENC+2
  STA HCE2,X
  LDA ENC+3
  STA HCE3,X
  LDA JDA
  STA HCAL,X
  LDA JDA+1
  STA HCAH,X
.ha_got:
  LDA JDA
  ORA JDA+1
  BEQ .ha_x
  LDX HCNT               ; there already?
.ha_dup:
  DEX
  BMI .ha_new
  LDA HDL,X
  CMP JDA
  BNE .ha_dup
  LDA HDH,X
  CMP JDA+1
  BNE .ha_dup
.ha_x:
  RTS
.ha_new:
  LDX HCNT
  LDA JDA
  STA HDL,X
  LDA JDA+1
  STA HDH,X
  LDY JROW
  LDA ROWLO,Y
  CLC
  ADC JWS
  STA HVL,X
  LDA ROWHI,Y
  ADC #0
  STA HVH,X
  LDA JWL
  CMP #16
  BCC .ha_1
  LDA #15
.ha_1:
  STA HLN,X
  INC HCNT
  RTS

; ISDIG: C = 1 if A is a digit
ISDIG:
  CMP #'0'
  BCC .id_no
  CMP #'9'+1
  BCS .id_no
  SEC
  RTS
.id_no:
  CLC
  RTS

; ISLET: C = 1 if A is a letter, then A in lower case
ISLET:
  CMP #'A'
  BCC .il_no
  CMP #'Z'+1
  BCC .il_up
  CMP #'a'
  BCC .il_no
  CMP #'z'+1
  BCC .il_yes
  BRA .il_no
.il_up:
  ORA #$20
.il_yes:
  SEC
  RTS
.il_no:
  CLC
  RTS

; IN_PICK: the place of SAVE / RESTORE: UP / DOWN change it, button 1 takes it, button 2 = none.
; A = 0-2, C = 1 none
IN_PICK:
  LDA #<MSG_PICK
  LDY #>MSG_PICK
  JSR PUTSTR
  LDA CURCOL
  STA PK_COL
  LDA #<MSG_PICK2
  LDY #>MSG_PICK2
  JSR PUTSTR
  LDA CURCOL
  PHA
.ip_d:
  LDA PK_COL             ; the number of the place
  STA CURCOL
  LDA SV_SLOT
  CLC
  ADC #'1'
  STA SV_NBUF
  STZ SV_NBUF+1
  LDA #<SV_NBUF
  LDY #>SV_NBUF
  JSR PUTSTR
.ip_e:
  JSR JOY_EVENT
  CMP #EV_UP
  BNE .ip_dn
  LDA SV_SLOT
  BEQ .ip_e
  DEC SV_SLOT
  BRA .ip_d
.ip_dn:
  CMP #EV_DOWN
  BNE .ip_ok
  LDA SV_SLOT
  CMP #2
  BCS .ip_e
  INC SV_SLOT
  BRA .ip_d
.ip_ok:
  CMP #EV_ADD
  BNE .ip_no
  PLA
  STA CURCOL
  LDA SV_SLOT
  CLC
  RTS
.ip_no:
  CMP #EV_SEND
  BNE .ip_e
  PLA
  STA CURCOL
  SEC
  RTS
PK_COL:      .byte 0
MSG_PICK:    .byte "PLACE ",0
MSG_PICK2:   .byte "1  UP/DOWN, BUTTON 1 = OK, 2 = NO",0
; ===============================================================
;  SAVE / RESTORE: three saved games per story on the SD
; ===============================================================
; SAVE and RESTORE list the 3 places (score and moves, or EMPTY)
; and ask for one (IN_PICK: a key 1-3, or the joystick).
; Place 1 = zone SAVE_ZONE (35-37, as before), places 2 and 3 =
; zones 2 x SAVE_ZONE - 26 and - 25 (44-49).
; A zone of the save area: sector 2 = header, sectors
; 3-15 = data (6.5 KB): the Z stack, then the dynamic memory as
; its difference (XOR) from the story on the SD, with the runs of
; zeros written as 0, length-1 (like the Quetzal format). The
; header is written last, so a broken save is never taken.
;   header: "MVST", version 1, zone, release (2), serial (6),
;   PC (3), FP and ZSP - ZSTACK (2 + 2), data bytes (2), sum (2),
;   score (2), moves (2)
; Both versions of a story (keyboard and joystick) share it.

SV_SEC      = $F0      ; data sector being written / read (0-12)
SV_RUN      = $F1      ; zeros still to give back (restore)
SV_PG       = $F2      ; page of the dynamic memory
SV_A        = $F3      ; RAM frame with the story page (high byte)
SV_B        = $F4      ; RAM frame of the sector buffer (high byte)
SV_SUM      = $F5      ; 2: sum of the data bytes
SV_LEN      = $F7      ; 2: data bytes
SV_P        = $F9      ; 2: pointer into the sector buffer
SV_Q        = $FB      ; 2: pointer into memory
SV_MODE     = $FD      ; 0 = check only (restore, first pass)
SV_OK       = $FE      ; result
SV_DATA     = 13       ; data sectors
SV_HDR      = 64       ; bytes of the header written

OP_SAVE:
  JSR SV_FRAMES
  JSR SV_PICK            ; which place
  BCC .sv_go
  JMP .sv_fail
.sv_go:
  JSR SV_OUTINIT
  ; the Z stack
  LDA #<ZSTACK
  STA SV_Q
  LDA #>ZSTACK
  STA SV_Q+1
.sv_stk:
  LDA SV_Q
  CMP ZSP
  BNE .sv_s1
  LDA SV_Q+1
  CMP ZSP+1
  BEQ .sv_mem
.sv_s1:
  LDA (SV_Q)
  JSR SV_PUT
  BCS .sv_fail
  INC SV_Q
  BNE .sv_stk
  INC SV_Q+1
  BRA .sv_stk
.sv_mem:
  ; the dynamic memory, page by page, XOR the story
  STZ SV_PG
  STZ SV_RUN
.sv_pg:
  LDA SV_A
  STA MHI
  LDA SV_PG
  JSR SD_PAGE
  LDA SV_PG
  ASL A
  CLC
  ADC #>ZBASE
  STA SV_Q+1
  STZ SV_Q
  LDA SV_A
  STA PTR+1
  STZ PTR
  LDX #2
.sv_half:
  LDY #0
.sv_b:
  LDA (SV_Q),Y
  EOR (PTR),Y
  BNE .sv_nz
  INC SV_RUN             ; one more zero
  BNE .sv_nx
  DEC SV_RUN             ; 255 zeros written out, this one starts a new run
  JSR SV_ZEROS
  BCS .sv_fail
  LDA #1
  STA SV_RUN
  BRA .sv_nx
.sv_nz:
  PHA
  JSR SV_ZEROS
  PLA
  BCS .sv_fail
  JSR SV_PUTY
  BCS .sv_fail
.sv_nx:
  INY
  BNE .sv_b
  INC SV_Q+1
  INC PTR+1
  DEX
  BNE .sv_half
  INC SV_PG
  LDA SV_PG
  CMP DYNP
  BCC .sv_pg
  JSR SV_ZEROS
  BCS .sv_fail
  JSR SV_FLUSH
  BCS .sv_fail
  ; header
  JSR SV_HEADER
  LDA SV_B
  JSR SV_WRITE0
  BCS .sv_fail
  JSR SV_RELEASE
  SEC
  JMP BRANCH
.sv_fail:
  JSR SV_RELEASE
  CLC
  JMP BRANCH

; SV_ZEROS: SV_RUN zeros waiting -> 0, run-1 (C = 1: full). Keeps X, Y
SV_ZEROS:
  LDA SV_RUN
  BEQ .sz_x
  LDA #0
  JSR SV_PUTY
  BCS .sz_f
  LDA SV_RUN
  DEC A
  JSR SV_PUTY
  BCS .sz_f
  STZ SV_RUN
.sz_x:
  CLC
.sz_f:
  RTS

; SV_PUT / SV_PUTY: byte A into the data (C = 1: no room). SV_PUTY keeps X, Y
SV_PUT:
SV_PUTY:
  PHY
  STA (SV_P)
  CLC
  ADC SV_SUM
  STA SV_SUM
  BCC .sp_1
  INC SV_SUM+1
.sp_1:
  INC SV_LEN
  BNE .sp_2
  INC SV_LEN+1
.sp_2:
  INC SV_P
  BNE .sp_ok
  INC SV_P+1
  LDA SV_P+1
  SEC
  SBC SV_B
  CMP #2
  BCC .sp_ok
  PHX
  JSR SV_FLUSH           ; the buffer is full: write it
  PLX
  BCS .sp_f
.sp_ok:
  PLY
  CLC
  RTS
.sp_f:
  PLY
  SEC
  RTS

; SV_FLUSH: the buffer into data sector SV_SEC (C = 1: no more sectors)
SV_FLUSH:
  LDA SV_SEC
  CMP #SV_DATA
  BCS .sf_x
  JSR SV_LBA
  LDA SV_B
  JSR SD_WRITE
  BCS .sf_x
  INC SV_SEC
  STZ SV_P
  LDA SV_B
  STA SV_P+1
  CLC
.sf_x:
  RTS

; SV_LBA: SD_LBA = data sector SV_SEC of the zone of the place chosen
SV_LBA:
  LDA SV_SEC
  SEC                    ; (+1: the data come after the header)
  ADC SV_BASE
  STA SD_LBA
  LDA SV_BASE+1
  ADC #0
  STA SD_LBA+1
  STZ SD_LBA+2
  STZ SD_LBA+3
  RTS

; SV_WRITE0 / SV_READ0: the header sector from / into RAM page A
SV_WRITE0:
  PHA
  JSR SV_LBA0
  PLA
  JMP SD_WRITE
SV_READ0:
  PHA
  JSR SV_LBA0
  PLA
  JMP SD_READ
SV_LBA0:
  LDA SV_BASE
  STA SD_LBA
  LDA SV_BASE+1
  STA SD_LBA+1
  STZ SD_LBA+2
  STZ SD_LBA+3
  RTS

; SD_WRITE: RAM page A -> sector SD_LBA (C = 1: error)
SD_WRITE:
  TAY
  SEI
  LDX #0
  JSR JT_SD_WRITE
  CLI
  RTS

; SV_OUTINIT: empty data
SV_OUTINIT:
  STZ SV_SEC
  STZ SV_SUM
  STZ SV_SUM+1
  STZ SV_LEN
  STZ SV_LEN+1
  STZ SV_P
  LDA SV_B
  STA SV_P+1
  RTS

; SV_HEADER: the header into the buffer SV_B
SV_HEADER:
  LDA SV_B
  STA SV_P+1
  STZ SV_P
  LDY #SV_HDR-1
  LDA #0
.sh_z:
  STA (SV_P),Y
  DEY
  BPL .sh_z
  LDY #0
  JSR SV_HDRDATA         ; signature and story (same bytes as the check)
  LDA PC0
  STA (SV_P),Y
  INY
  LDA PC1
  STA (SV_P),Y
  INY
  LDA PC2
  STA (SV_P),Y
  INY
  LDA FP
  SEC
  SBC #<ZSTACK
  STA (SV_P),Y
  INY
  LDA FP+1
  SBC #>ZSTACK
  STA (SV_P),Y
  INY
  LDA ZSP
  SEC
  SBC #<ZSTACK
  STA (SV_P),Y
  INY
  LDA ZSP+1
  SBC #>ZSTACK
  STA (SV_P),Y
  INY
  LDA SV_LEN
  STA (SV_P),Y
  INY
  LDA SV_LEN+1
  STA (SV_P),Y
  INY
  LDA SV_SUM
  STA (SV_P),Y
  INY
  LDA SV_SUM+1
  STA (SV_P),Y
  INY
  LDA #17                ; the score and the moves (for the list of the places)
  JSR .sh_var
  LDA #18
.sh_var:
  PHY
  JSR GETVAR
  PLY
  LDA VAL
  STA (SV_P),Y
  INY
  LDA VAL+1
  STA (SV_P),Y
  INY
  RTS
; SV_HDRDATA: bytes 0-13 of the header (Y = 0 in, 14 out)
SV_HDRDATA:
.hd_lp:
  LDA SV_SIG,Y
  STA (SV_P),Y
  INY
  CPY #14
  BCC .hd_lp
  RTS
SV_SIG:
  .byte "MVST",1,SAVE_ZONE,<ST_REL,>ST_REL
ST_SERIAL2:
  .byte 0,0,0,0,0,0      ; the serial, copied from ST_SERIAL at the start

; ---------------- the three places ----------------
SV_BASE:   .word 0       ; header sector of the place chosen (32768 + zone * 16 + 2)
SV_SLOT:   .byte 0       ; the place shown / chosen (0-2)
SV_NBUF:   .byte 0,0,0,0,0,0,0,0
SV_ZTAB:   .byte SAVE_ZONE, SAVE_ZONE*2-26, SAVE_ZONE*2-25

; SV_SETZONE: A = place 0-2: SV_BASE and the zone in the signature
SV_SETZONE:
  TAX
  LDA SV_ZTAB,X
  STA SV_SIG+5
  PHA
  ASL A                  ; zone * 16 + 2
  ASL A
  ASL A
  ASL A
  CLC
  ADC #2
  STA SV_BASE
  PLA
  LSR A
  LSR A
  LSR A
  LSR A
  CLC
  ADC #$80               ; (32768 = $8000)
  STA SV_BASE+1
  RTS

; SV_PICK: the three places (score and moves, or EMPTY), then IN_PICK asks for one:
; C = 0 and the zone set (A = place), C = 1 nothing chosen
SV_PICK:
  JSR FLUSHW
  LDA CURCOL             ; on a new row
  BEQ .pk_l0
  JSR NEWLINE
.pk_l0:
  STZ SV_SLOT
.pk_l:
  LDA SV_SLOT
  JSR SV_SETZONE
  LDA SV_B               ; its header
  JSR SV_READ0
  LDA #<SV_TSLOT
  LDY #>SV_TSLOT
  JSR PUTSTR
  LDA SV_SLOT
  CLC
  ADC #'1'
  STA SV_NBUF
  STZ SV_NBUF+1
  LDA #<SV_NBUF
  LDY #>SV_NBUF
  JSR PUTSTR
  LDA SV_B
  STA SV_P+1
  STZ SV_P
  LDY #0
.pk_sig:
  LDA (SV_P),Y
  CMP SV_SIG,Y
  BNE .pk_empty
  INY
  CPY #14
  BCC .pk_sig
  LDA #<SV_TSCORE
  LDY #>SV_TSCORE
  JSR PUTSTR
  LDY #25
  JSR .pk_num
  LDA #<SV_TMOVES
  LDY #>SV_TMOVES
  JSR PUTSTR
  LDY #27
  JSR .pk_num
  BRA .pk_n
.pk_empty:
  LDA #<SV_TEMPTY
  LDY #>SV_TEMPTY
  JSR PUTSTR
.pk_n:
  JSR NEWLINE
  INC SV_SLOT
  LDA SV_SLOT
  CMP #3
  BCC .pk_l
  STZ SV_SLOT
  JSR IN_PICK            ; A = 0-2, C = 1: no
  PHP
  PHA
  JSR NEWLINE
  PLA
  PLP
  BCS .pk_x
  PHA
  JSR SV_SETZONE
  PLA
  CLC
.pk_x:
  RTS
.pk_num:                 ; the number at byte Y of the header
  LDA (SV_P),Y
  STA VAL
  INY
  LDA (SV_P),Y
  STA VAL+1
  JSR NUMSTR
  STZ SV_NBUF,X
.pk_c:
  DEX
  BMI .pk_p
  LDA NUMBUF,X
  STA SV_NBUF,X
  BRA .pk_c
.pk_p:
  LDA #<SV_NBUF
  LDY #>SV_NBUF
  JMP PUTSTR
SV_TSLOT:  .byte "PLACE ",0
SV_TSCORE: .byte ": SCORE ",0
SV_TMOVES: .byte ", MOVES ",0
SV_TEMPTY: .byte ": EMPTY",0

; SV_FRAMES: two RAM frames for the buffers (out of the cache until SV_RELEASE)
SV_FRAMES:
  JSR FLUSHW
  LDX #5
.sf_ser:
  LDA ST_SERIAL,X
  STA ST_SERIAL2,X
  DEX
  BPL .sf_ser
  JSR RAM_SCRATCH
  LDA MHI
  STA SV_A
  JSR RAM_SCRATCH
  LDA MHI
  STA SV_B
  RTS
; SV_RELEASE: the two frames back to the cache (free)
SV_RELEASE:
  LDA SV_A
  JSR .sr_one
  LDA SV_B
.sr_one:
  SEC
  SBC FR0
  LSR A
  TAY
  LDA #0
  STA FOWN,Y
  RTS

; ---------------- RESTORE ----------------
OP_RESTORE:
  JSR SV_FRAMES
  JSR SV_PICK            ; which place
  BCC .rs_go
  JMP .rs_fail
.rs_go:
  LDA SV_B               ; the header
  JSR SV_READ0
  LDA SV_B
  STA SV_P+1
  STZ SV_P
  LDY #0
.rs_sig:
  LDA (SV_P),Y
  CMP SV_SIG,Y
  BNE .rs_fail
  INY
  CPY #14
  BCC .rs_sig
  LDY #14                ; PC, FP, ZSP, length, sum
  LDX #0
.rs_h:
  LDA (SV_P),Y
  STA SV_HEAD,X
  INY
  INX
  CPX #11
  BCC .rs_h
  ; first pass: the sum; second pass: the stack and the memory
  STZ SV_MODE
  JSR SV_STREAM
  LDA SV_SUM
  CMP SV_HEAD+9
  BNE .rs_fail
  LDA SV_SUM+1
  CMP SV_HEAD+10
  BNE .rs_fail
  LDA #1
  STA SV_MODE
  JSR SV_STREAM
  ; registers
  LDA SV_HEAD
  STA PC0
  LDA SV_HEAD+1
  STA PC1
  LDA SV_HEAD+2
  STA PC2
  CLC
  LDA SV_HEAD+3
  ADC #<ZSTACK
  STA FP
  LDA SV_HEAD+4
  ADC #>ZSTACK
  STA FP+1
  CLC
  LDA SV_HEAD+5
  ADC #<ZSTACK
  STA ZSP
  LDA SV_HEAD+6
  ADC #>ZSTACK
  STA ZSP+1
  JSR SV_RELEASE
  LDA #$FF
  STA SAF
  JSR PC_LOAD
  SEC
  JMP BRANCH
.rs_fail:
  JSR SV_RELEASE
  CLC
  JMP BRANCH
SV_HEAD = LINEBUF        ; 11 bytes: PC (3), FP (2), ZSP (2), length (2), sum (2)

; SV_STREAM: reads the data; SV_MODE 0 = only the sum, 1 = into the stack and the memory
SV_STREAM:
  STZ SV_SEC
  STZ SV_SUM
  STZ SV_SUM+1
  JSR SV_INLOAD
  ; stack: ZSP - ZSTACK bytes
  LDA #<ZSTACK
  STA SV_Q
  LDA #>ZSTACK
  STA SV_Q+1
  CLC
  LDA SV_HEAD+5
  ADC #<ZSTACK
  STA T0
  LDA SV_HEAD+6
  ADC #>ZSTACK
  STA T1
.ss_stk:
  LDA SV_Q
  CMP T0
  BNE .ss_s1
  LDA SV_Q+1
  CMP T1
  BEQ .ss_mem
.ss_s1:
  JSR SV_GET
  LDX SV_MODE
  BEQ .ss_s2
  STA (SV_Q)
.ss_s2:
  INC SV_Q
  BNE .ss_stk
  INC SV_Q+1
  BRA .ss_stk
.ss_mem:
  STZ SV_PG
  STZ SV_RUN
.ss_pg:
  LDA SV_PG              ; the story page, straight into the dynamic memory (pass 2)
  ASL A
  CLC
  ADC #>ZBASE
  STA SV_Q+1
  STZ SV_Q
  LDA SV_MODE
  BEQ .ss_nopg
  LDA SV_Q+1
  STA MHI
  LDA SV_PG
  JSR SD_PAGE
.ss_nopg:
  LDX #2
.ss_half:
  LDY #0
.ss_b:
  LDA SV_RUN
  BEQ .ss_get
  DEC SV_RUN             ; a zero: the byte stays
  BRA .ss_nx
.ss_get:
  JSR SV_GETY
  CMP #0
  BNE .ss_x
  JSR SV_GETY            ; 0, n-1: n zeros, this one included
  STA SV_RUN
  BRA .ss_nx
.ss_x:
  PHA
  LDA SV_MODE
  BEQ .ss_nox
  PLA
  EOR (SV_Q),Y
  STA (SV_Q),Y
  BRA .ss_nx
.ss_nox:
  PLA
.ss_nx:
  INY
  BNE .ss_b
  INC SV_Q+1
  DEX
  BNE .ss_half
  INC SV_PG
  LDA SV_PG
  CMP DYNP
  BCC .ss_pg
  RTS

; SV_INLOAD: data sector SV_SEC into the buffer, SV_P at its start
SV_INLOAD:
  JSR SV_LBA
  LDA SV_B
  JSR SD_READ
  STZ SV_P
  LDA SV_B
  STA SV_P+1
  RTS

; SV_GET / SV_GETY: next data byte (adds it to the sum). Keeps X, Y
SV_GET:
SV_GETY:
  PHY
  PHX
  LDA SV_P+1             ; end of the buffer: the next sector
  SEC
  SBC SV_B
  CMP #2
  BCC .sg_1
  INC SV_SEC
  JSR SV_INLOAD
.sg_1:
  LDA (SV_P)
  PHA
  CLC
  ADC SV_SUM
  STA SV_SUM
  BCC .sg_2
  INC SV_SUM+1
.sg_2:
  INC SV_P
  BNE .sg_3
  INC SV_P+1
.sg_3:
  PLA
  PLX
  PLY
  RTS

; ---------------- story 1 (generated) ----------------
; story 1: zork1.z3 (generated by gen_zm.js)
ST_NUM      = 1
ST_REL      = 119
ST_DYN      = $2C12      ; dynamic memory
ST_LEN      = $A99B      ; length / 2
ST_SUM      = $BF44

ST_SERIAL:  .byte "880429"
ST_TITLE:   .byte "ZORK I",0
ST_SUB:     .byte "The Great Underground Empire",0
ST_COPY:    .byte "(C) 1980-1986 INFOCOM, INC.",0

; word lists of the joystick menu
WL_GO:
  .byte "north",0
  .byte "south",0
  .byte "east",0
  .byte "west",0
  .byte "northeast",0
  .byte "northwest",0
  .byte "southeast",0
  .byte "southwest",0
  .byte "up",0
  .byte "down",0
  .byte "in",0
  .byte "out",0
  .byte 0
WL_VERB:
  .byte "take",0
  .byte "drop",0
  .byte "open",0
  .byte "close",0
  .byte "examine",0
  .byte "read",0
  .byte "put",0
  .byte "give",0
  .byte "turn",0
  .byte "move",0
  .byte "push",0
  .byte "pull",0
  .byte "light",0
  .byte "extinguish",0
  .byte "kill",0
  .byte "attack",0
  .byte "throw",0
  .byte "climb",0
  .byte "enter",0
  .byte "exit",0
  .byte "tie",0
  .byte "untie",0
  .byte "unlock",0
  .byte "lock",0
  .byte "wave",0
  .byte "ring",0
  .byte "eat",0
  .byte "drink",0
  .byte "fill",0
  .byte "pour",0
  .byte "dig",0
  .byte "inflate",0
  .byte "deflate",0
  .byte "launch",0
  .byte "board",0
  .byte "disembark",0
  .byte "wind",0
  .byte "raise",0
  .byte "lower",0
  .byte "search",0
  .byte "listen",0
  .byte "smell",0
  .byte "touch",0
  .byte "rub",0
  .byte "say",0
  .byte "answer",0
  .byte "wake",0
  .byte "jump",0
  .byte "swim",0
  .byte "pray",0
  .byte "wear",0
  .byte "break",0
  .byte "burn",0
  .byte "cut",0
  .byte "look",0
  .byte "go",0
  .byte "wait",0
  .byte "follow",0
  .byte "hello",0
  .byte "echo",0
  .byte "odysseus",0
  .byte 0
WL_WORD:
  .byte "with",0
  .byte "in",0
  .byte "on",0
  .byte "to",0
  .byte "from",0
  .byte "at",0
  .byte "under",0
  .byte "into",0
  .byte "out",0
  .byte "up",0
  .byte "down",0
  .byte "over",0
  .byte "through",0
  .byte "behind",0
  .byte "all",0
  .byte "it",0
  .byte "and",0
  .byte "but",0
  .byte "except",0
  .byte "the",0
  .byte "yes",0
  .byte "no",0
  .byte "0",0
  .byte "1",0
  .byte "2",0
  .byte "3",0
  .byte "4",0
  .byte "5",0
  .byte "6",0
  .byte "7",0
  .byte "8",0
  .byte "9",0
  .byte 0
WL_GAME:
  .byte "look",0
  .byte "inventory",0
  .byte "wait",0
  .byte "again",0
  .byte "score",0
  .byte "diagnose",0
  .byte "save",0
  .byte "restore",0
  .byte "restart",0
  .byte "brief",0
  .byte "verbose",0
  .byte "yes",0
  .byte "no",0
  .byte "quit",0
  .byte 0

CODE_END:

; font of the miniVIC BIOS (crt_text_drv.s) with new g j p q y, 128 characters of 6 x 8 (generated by gen_zm.js)
FONT:
  .byte $00,$00,$00,$FF,$FF,$00,$00,$00
  .byte $18,$18,$18,$18,$18,$18,$18,$18
  .byte $00,$00,$00,$F8,$F8,$18,$18,$18
  .byte $00,$00,$00,$1F,$1F,$18,$18,$18
  .byte $18,$18,$18,$F8,$F8,$00,$00,$00
  .byte $18,$18,$18,$1F,$1F,$00,$00,$00
  .byte $18,$18,$18,$FF,$FF,$18,$18,$18
  .byte $07,$07,$07,$07,$07,$07,$07,$00
  .byte $08,$08,$08,$08,$08,$08,$08,$00
  .byte $09,$09,$09,$09,$09,$09,$09,$00
  .byte $0A,$0A,$0A,$0A,$0A,$0A,$0A,$00
  .byte $0B,$0B,$0B,$0B,$0B,$0B,$0B,$00
  .byte $0C,$0C,$0C,$0C,$0C,$0C,$0C,$00
  .byte $0D,$0D,$0D,$0D,$0D,$0D,$0D,$00
  .byte $0E,$0E,$0E,$0E,$0E,$0E,$0E,$00
  .byte $0F,$0F,$0F,$0F,$0F,$0F,$0F,$00
  .byte $10,$10,$10,$10,$10,$10,$10,$00
  .byte $11,$11,$11,$11,$11,$11,$11,$00
  .byte $12,$12,$12,$12,$12,$12,$12,$00
  .byte $13,$13,$13,$13,$13,$13,$13,$00
  .byte $14,$14,$14,$14,$14,$14,$14,$00
  .byte $15,$15,$15,$15,$15,$15,$15,$00
  .byte $16,$16,$16,$16,$16,$16,$16,$00
  .byte $17,$17,$17,$17,$17,$17,$17,$00
  .byte $18,$18,$18,$18,$18,$18,$18,$00
  .byte $19,$19,$19,$19,$19,$19,$19,$00
  .byte $1A,$1A,$1A,$1A,$1A,$1A,$1A,$00
  .byte $1B,$1B,$1B,$1B,$1B,$1B,$1B,$00
  .byte $1C,$1C,$1C,$1C,$1C,$1C,$1C,$00
  .byte $1D,$1D,$1D,$1D,$1D,$1D,$1D,$00
  .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$00
  .byte $1F,$1F,$1F,$1F,$1F,$1F,$1F,$00
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
  .byte $40,$20,$10,$00,$00,$00,$00,$00
  .byte $00,$00,$70,$88,$88,$98,$68,$00
  .byte $80,$80,$F0,$88,$88,$88,$F0,$00
  .byte $00,$00,$78,$80,$80,$80,$78,$00
  .byte $08,$08,$78,$88,$88,$88,$78,$00
  .byte $00,$00,$70,$88,$F8,$80,$78,$00
  .byte $30,$40,$E0,$40,$40,$40,$40,$00
  .byte $00,$00,$78,$88,$88,$78,$08,$70
  .byte $80,$80,$F0,$88,$88,$88,$88,$00
  .byte $00,$40,$00,$40,$40,$40,$40,$00
  .byte $00,$10,$00,$10,$10,$10,$90,$60
  .byte $00,$80,$80,$A0,$C0,$A0,$90,$00
  .byte $C0,$40,$40,$40,$40,$40,$60,$00
  .byte $00,$00,$D8,$A8,$A8,$A8,$A8,$00
  .byte $00,$00,$F0,$88,$88,$88,$88,$00
  .byte $00,$00,$70,$88,$88,$88,$70,$00
  .byte $00,$00,$F0,$88,$88,$F0,$80,$80
  .byte $00,$00,$78,$88,$88,$78,$08,$08
  .byte $00,$00,$70,$88,$80,$80,$80,$00
  .byte $00,$00,$78,$80,$70,$08,$F0,$00
  .byte $40,$40,$F0,$40,$40,$40,$30,$00
  .byte $00,$00,$88,$88,$88,$88,$78,$00
  .byte $00,$00,$88,$88,$90,$A0,$40,$00
  .byte $00,$00,$88,$88,$88,$A8,$D8,$00
  .byte $00,$00,$88,$50,$20,$50,$88,$00
  .byte $00,$00,$88,$88,$88,$78,$08,$70
  .byte $00,$00,$F8,$10,$20,$40,$F8,$00
  .byte $38,$40,$20,$C0,$20,$40,$38,$00
  .byte $40,$40,$40,$00,$40,$40,$40,$00
  .byte $E0,$10,$20,$18,$20,$10,$E0,$00
  .byte $00,$00,$24,$00,$00,$42,$3C,$00
  .byte $A8,$50,$A8,$50,$A8,$50,$A8,$00
