'use strict';
// minivic.js - minimal miniVIC emulator used to take the screenshots of the games
//
//   CPU  W65C02S at 1 MHz (65C02 instructions, approximate cycles)
//   VDP  TMS9918A: Graphics I/II + sprites, NMI at the vblank (60 Hz)
//   VIA  joysticks: PORTB $D580 (P2), PORTA $D581 (P1), active low
//   AY   writes to $D380-$D385 are ignored (no audio; tools/aywav.js records them)
//
// The NMI handler of the BIOS is replaced by a stub at $FF00:
//   PHA PHX PHY / JSR $0FD0 / LDA $B001 / PLY PLX PLA / RTI

const zlib = require('zlib');

const CYCLES_PER_FRAME = 16667;           // 1 MHz / 60 Hz

// ---------------- CPU ----------------
const C = 0x01, Z = 0x02, I = 0x04, D = 0x08, B = 0x10, U = 0x20, V = 0x40, N = 0x80;

// "opcode mnemonic mode cycles"
const OPTAB = `
69 ADC imm 2|65 ADC zp 3|75 ADC zpx 4|6D ADC abs 4|7D ADC abx 4|79 ADC aby 4|61 ADC izx 6|71 ADC izy 5|72 ADC izp 5
29 AND imm 2|25 AND zp 3|35 AND zpx 4|2D AND abs 4|3D AND abx 4|39 AND aby 4|21 AND izx 6|31 AND izy 5|32 AND izp 5
0A ASL acc 2|06 ASL zp 5|16 ASL zpx 6|0E ASL abs 6|1E ASL abx 7
90 BCC rel 2|B0 BCS rel 2|F0 BEQ rel 2|30 BMI rel 2|D0 BNE rel 2|10 BPL rel 2|80 BRA rel 3|50 BVC rel 2|70 BVS rel 2
24 BIT zp 3|2C BIT abs 4|34 BIT zpx 4|3C BIT abx 4|89 BITI imm 2
00 BRK imp 7|18 CLC imp 2|D8 CLD imp 2|58 CLI imp 2|B8 CLV imp 2
C9 CMP imm 2|C5 CMP zp 3|D5 CMP zpx 4|CD CMP abs 4|DD CMP abx 4|D9 CMP aby 4|C1 CMP izx 6|D1 CMP izy 5|D2 CMP izp 5
E0 CPX imm 2|E4 CPX zp 3|EC CPX abs 4|C0 CPY imm 2|C4 CPY zp 3|CC CPY abs 4
3A DEC acc 2|C6 DEC zp 5|D6 DEC zpx 6|CE DEC abs 6|DE DEC abx 7|CA DEX imp 2|88 DEY imp 2
49 EOR imm 2|45 EOR zp 3|55 EOR zpx 4|4D EOR abs 4|5D EOR abx 4|59 EOR aby 4|41 EOR izx 6|51 EOR izy 5|52 EOR izp 5
1A INC acc 2|E6 INC zp 5|F6 INC zpx 6|EE INC abs 6|FE INC abx 7|E8 INX imp 2|C8 INY imp 2
4C JMP abs 3|6C JMP ind 6|7C JMP iax 6|20 JSR abs 6
A9 LDA imm 2|A5 LDA zp 3|B5 LDA zpx 4|AD LDA abs 4|BD LDA abx 4|B9 LDA aby 4|A1 LDA izx 6|B1 LDA izy 5|B2 LDA izp 5
A2 LDX imm 2|A6 LDX zp 3|B6 LDX zpy 4|AE LDX abs 4|BE LDX aby 4
A0 LDY imm 2|A4 LDY zp 3|B4 LDY zpx 4|AC LDY abs 4|BC LDY abx 4
4A LSR acc 2|46 LSR zp 5|56 LSR zpx 6|4E LSR abs 6|5E LSR abx 7|EA NOP imp 2
09 ORA imm 2|05 ORA zp 3|15 ORA zpx 4|0D ORA abs 4|1D ORA abx 4|19 ORA aby 4|01 ORA izx 6|11 ORA izy 5|12 ORA izp 5
48 PHA imp 3|08 PHP imp 3|DA PHX imp 3|5A PHY imp 3|68 PLA imp 4|28 PLP imp 4|FA PLX imp 4|7A PLY imp 4
2A ROL acc 2|26 ROL zp 5|36 ROL zpx 6|2E ROL abs 6|3E ROL abx 7
6A ROR acc 2|66 ROR zp 5|76 ROR zpx 6|6E ROR abs 6|7E ROR abx 7
40 RTI imp 6|60 RTS imp 6
E9 SBC imm 2|E5 SBC zp 3|F5 SBC zpx 4|ED SBC abs 4|FD SBC abx 4|F9 SBC aby 4|E1 SBC izx 6|F1 SBC izy 5|F2 SBC izp 5
38 SEC imp 2|F8 SED imp 2|78 SEI imp 2
85 STA zp 3|95 STA zpx 4|8D STA abs 4|9D STA abx 5|99 STA aby 5|81 STA izx 6|91 STA izy 6|92 STA izp 5
86 STX zp 3|96 STX zpy 4|8E STX abs 4|84 STY zp 3|94 STY zpx 4|8C STY abs 4
64 STZ zp 3|74 STZ zpx 4|9C STZ abs 4|9E STZ abx 5
AA TAX imp 2|A8 TAY imp 2|BA TSX imp 2|8A TXA imp 2|9A TXS imp 2|98 TYA imp 2
14 TRB zp 5|1C TRB abs 6|04 TSB zp 5|0C TSB abs 6|CB WAI imp 3|DB STP imp 3`;

const OPS = new Array(256).fill(null);
for (const e of OPTAB.split(/[|\n]/)) {
  const t = e.trim().split(/\s+/);
  if (t.length === 4) OPS[parseInt(t[0], 16)] = { mn: t[1], mode: t[2], cyc: +t[3] };
}
for (let n = 0; n < 8; n++) {                       // Rockwell bit instructions
  OPS[0x07 + n * 16] = { mn: 'RMB', mode: 'zp', cyc: 5, bit: n };
  OPS[0x87 + n * 16] = { mn: 'SMB', mode: 'zp', cyc: 5, bit: n };
  OPS[0x0F + n * 16] = { mn: 'BBR', mode: 'zpr', cyc: 5, bit: n };
  OPS[0x8F + n * 16] = { mn: 'BBS', mode: 'zpr', cyc: 5, bit: n };
}

class CPU {
  constructor(bus) {
    this.bus = bus;
    this.a = 0; this.x = 0; this.y = 0; this.sp = 0xFF; this.pc = 0; this.p = U | I;
    this.cycles = 0; this.waiting = false; this.stopped = false; this.bad = null;
  }
  rd(a) { return this.bus.read(a & 0xFFFF); }
  wr(a, v) { this.bus.write(a & 0xFFFF, v & 0xFF); }
  rd16(a) { return this.rd(a) | (this.rd(a + 1) << 8); }
  zp16(z) { return this.rd(z & 0xFF) | (this.rd((z + 1) & 0xFF) << 8); }
  push(v) { this.wr(0x100 | this.sp, v); this.sp = (this.sp - 1) & 0xFF; }
  pull() { this.sp = (this.sp + 1) & 0xFF; return this.rd(0x100 | this.sp); }
  nz(v) { this.p = (this.p & ~(N | Z)) | (v & N) | (v ? 0 : Z); return v; }
  flag(f, on) { if (on) this.p |= f; else this.p &= ~f; }

  nmi() {
    this.waiting = false;
    this.push(this.pc >> 8); this.push(this.pc & 0xFF);
    this.push((this.p & ~B) | U);
    this.p = (this.p | I) & ~D;
    this.pc = this.rd16(0xFFFA);
    this.cycles += 7;
  }

  adc(v) {
    const c = this.p & C;
    if (this.p & D) {
      let lo = (this.a & 0x0F) + (v & 0x0F) + c;
      let hi = (this.a >> 4) + (v >> 4);
      if (lo > 9) { lo -= 10; hi++; }
      const bin = (this.a + v + c) & 0xFF;
      this.flag(V, (~(this.a ^ v) & (this.a ^ bin)) & 0x80);
      this.flag(C, hi > 9);
      if (hi > 9) hi -= 10;
      this.a = this.nz(((hi << 4) | (lo & 0x0F)) & 0xFF);
    } else {
      const r = this.a + v + c;
      this.flag(V, (~(this.a ^ v) & (this.a ^ r)) & 0x80);
      this.flag(C, r > 0xFF);
      this.a = this.nz(r & 0xFF);
    }
  }
  sbc(v) {
    const b = (this.p & C) ? 0 : 1;
    const r = this.a - v - b;
    this.flag(V, ((this.a ^ v) & (this.a ^ r)) & 0x80);
    if (this.p & D) {
      let lo = (this.a & 0x0F) - (v & 0x0F) - b;
      let hi = (this.a >> 4) - (v >> 4);
      if (lo < 0) { lo += 10; hi--; }
      if (hi < 0) hi += 10;
      this.flag(C, r >= 0);
      this.a = this.nz(((hi << 4) | (lo & 0x0F)) & 0xFF);
    } else {
      this.flag(C, r >= 0);
      this.a = this.nz(r & 0xFF);
    }
  }
  cmp(r, v) { const t = r - v; this.flag(C, t >= 0); this.nz(t & 0xFF); }

  step() {
    if (this.waiting || this.stopped) { this.cycles += 3; return; }
    const pc0 = this.pc;
    const opc = this.rd(this.pc); this.pc = (this.pc + 1) & 0xFFFF;
    const op = OPS[opc];
    if (!op) { this.bad = { opc, pc: pc0 }; this.stopped = true; return; }
    let ea = 0;
    switch (op.mode) {
      case 'imm': ea = this.pc; this.pc++; break;
      case 'zp':  ea = this.rd(this.pc++); break;
      case 'zpx': ea = (this.rd(this.pc++) + this.x) & 0xFF; break;
      case 'zpy': ea = (this.rd(this.pc++) + this.y) & 0xFF; break;
      case 'abs': ea = this.rd16(this.pc); this.pc += 2; break;
      case 'abx': ea = (this.rd16(this.pc) + this.x) & 0xFFFF; this.pc += 2; break;
      case 'aby': ea = (this.rd16(this.pc) + this.y) & 0xFFFF; this.pc += 2; break;
      case 'izx': ea = this.zp16(this.rd(this.pc++) + this.x); break;
      case 'izy': ea = (this.zp16(this.rd(this.pc++)) + this.y) & 0xFFFF; break;
      case 'izp': ea = this.zp16(this.rd(this.pc++)); break;
      case 'ind': ea = this.rd16(this.rd16(this.pc)); this.pc += 2; break;
      case 'iax': ea = this.rd16((this.rd16(this.pc) + this.x) & 0xFFFF); this.pc += 2; break;
      case 'rel': { const o = this.rd(this.pc++); ea = (this.pc + (o < 128 ? o : o - 256)) & 0xFFFF; break; }
      case 'zpr': { ea = this.rd(this.pc++); const o = this.rd(this.pc++); op.target = (this.pc + (o < 128 ? o : o - 256)) & 0xFFFF; break; }
    }
    this.pc &= 0xFFFF;
    this.cycles += op.cyc;
    const acc = op.mode === 'acc';
    let v, r;
    switch (op.mn) {
      case 'LDA': this.a = this.nz(this.rd(ea)); break;
      case 'LDX': this.x = this.nz(this.rd(ea)); break;
      case 'LDY': this.y = this.nz(this.rd(ea)); break;
      case 'STA': this.wr(ea, this.a); break;
      case 'STX': this.wr(ea, this.x); break;
      case 'STY': this.wr(ea, this.y); break;
      case 'STZ': this.wr(ea, 0); break;
      case 'ADC': this.adc(this.rd(ea)); break;
      case 'SBC': this.sbc(this.rd(ea)); break;
      case 'AND': this.a = this.nz(this.a & this.rd(ea)); break;
      case 'ORA': this.a = this.nz(this.a | this.rd(ea)); break;
      case 'EOR': this.a = this.nz(this.a ^ this.rd(ea)); break;
      case 'CMP': this.cmp(this.a, this.rd(ea)); break;
      case 'CPX': this.cmp(this.x, this.rd(ea)); break;
      case 'CPY': this.cmp(this.y, this.rd(ea)); break;
      case 'BIT': v = this.rd(ea); this.flag(Z, !(this.a & v)); this.p = (this.p & ~(N | V)) | (v & (N | V)); break;
      case 'BITI': this.flag(Z, !(this.a & this.rd(ea))); break;
      case 'ASL': v = acc ? this.a : this.rd(ea); this.flag(C, v & 0x80); r = this.nz((v << 1) & 0xFF); acc ? this.a = r : this.wr(ea, r); break;
      case 'LSR': v = acc ? this.a : this.rd(ea); this.flag(C, v & 1); r = this.nz(v >> 1); acc ? this.a = r : this.wr(ea, r); break;
      case 'ROL': v = acc ? this.a : this.rd(ea); r = this.nz(((v << 1) | (this.p & C)) & 0xFF); this.flag(C, v & 0x80); acc ? this.a = r : this.wr(ea, r); break;
      case 'ROR': v = acc ? this.a : this.rd(ea); r = this.nz((v >> 1) | ((this.p & C) << 7)); this.flag(C, v & 1); acc ? this.a = r : this.wr(ea, r); break;
      case 'INC': if (acc) this.a = this.nz((this.a + 1) & 0xFF); else this.wr(ea, this.nz((this.rd(ea) + 1) & 0xFF)); break;
      case 'DEC': if (acc) this.a = this.nz((this.a - 1) & 0xFF); else this.wr(ea, this.nz((this.rd(ea) - 1) & 0xFF)); break;
      case 'INX': this.x = this.nz((this.x + 1) & 0xFF); break;
      case 'INY': this.y = this.nz((this.y + 1) & 0xFF); break;
      case 'DEX': this.x = this.nz((this.x - 1) & 0xFF); break;
      case 'DEY': this.y = this.nz((this.y - 1) & 0xFF); break;
      case 'TAX': this.x = this.nz(this.a); break;
      case 'TAY': this.y = this.nz(this.a); break;
      case 'TXA': this.a = this.nz(this.x); break;
      case 'TYA': this.a = this.nz(this.y); break;
      case 'TSX': this.x = this.nz(this.sp); break;
      case 'TXS': this.sp = this.x; break;
      case 'TSB': v = this.rd(ea); this.flag(Z, !(v & this.a)); this.wr(ea, v | this.a); break;
      case 'TRB': v = this.rd(ea); this.flag(Z, !(v & this.a)); this.wr(ea, v & ~this.a); break;
      case 'RMB': this.wr(ea, this.rd(ea) & ~(1 << op.bit)); break;
      case 'SMB': this.wr(ea, this.rd(ea) | (1 << op.bit)); break;
      case 'BBR': if (!(this.rd(ea) & (1 << op.bit))) this.pc = op.target; break;
      case 'BBS': if (this.rd(ea) & (1 << op.bit)) this.pc = op.target; break;
      case 'BCC': if (!(this.p & C)) { this.pc = ea; this.cycles++; } break;
      case 'BCS': if (this.p & C) { this.pc = ea; this.cycles++; } break;
      case 'BNE': if (!(this.p & Z)) { this.pc = ea; this.cycles++; } break;
      case 'BEQ': if (this.p & Z) { this.pc = ea; this.cycles++; } break;
      case 'BPL': if (!(this.p & N)) { this.pc = ea; this.cycles++; } break;
      case 'BMI': if (this.p & N) { this.pc = ea; this.cycles++; } break;
      case 'BVC': if (!(this.p & V)) { this.pc = ea; this.cycles++; } break;
      case 'BVS': if (this.p & V) { this.pc = ea; this.cycles++; } break;
      case 'BRA': this.pc = ea; break;
      case 'JMP': this.pc = ea; break;
      case 'JSR': { const ret = (this.pc - 1) & 0xFFFF; this.push(ret >> 8); this.push(ret & 0xFF); this.pc = ea; break; }
      case 'RTS': this.pc = ((this.pull() | (this.pull() << 8)) + 1) & 0xFFFF; break;
      case 'RTI': this.p = this.pull() | U; this.pc = this.pull() | (this.pull() << 8); break;
      case 'PHA': this.push(this.a); break;
      case 'PHX': this.push(this.x); break;
      case 'PHY': this.push(this.y); break;
      case 'PHP': this.push(this.p | B | U); break;
      case 'PLA': this.a = this.nz(this.pull()); break;
      case 'PLX': this.x = this.nz(this.pull()); break;
      case 'PLY': this.y = this.nz(this.pull()); break;
      case 'PLP': this.p = this.pull() | U; break;
      case 'CLC': this.p &= ~C; break;
      case 'SEC': this.p |= C; break;
      case 'CLD': this.p &= ~D; break;
      case 'SED': this.p |= D; break;
      case 'CLI': this.p &= ~I; break;
      case 'SEI': this.p |= I; break;
      case 'CLV': this.p &= ~V; break;
      case 'NOP': break;
      case 'WAI': this.waiting = true; break;
      case 'STP': this.stopped = true; break;
      case 'BRK': {
        const ret = (this.pc + 1) & 0xFFFF;
        this.push(ret >> 8); this.push(ret & 0xFF); this.push(this.p | B | U);
        this.p = (this.p | I) & ~D; this.pc = this.rd16(0xFFFE); break;
      }
    }
  }
}

// ---------------- VDP TMS9918A ----------------
const PALETTE = [
  [0, 0, 0], [0, 0, 0], [33, 200, 66], [94, 220, 120], [84, 85, 237], [125, 118, 252],
  [212, 82, 77], [66, 235, 245], [252, 85, 84], [255, 121, 120], [212, 193, 84],
  [230, 206, 128], [33, 176, 59], [201, 91, 186], [204, 204, 204], [255, 255, 255],
];

class VDP {
  constructor() {
    this.vram = new Uint8Array(0x4000);
    this.reg = new Uint8Array(8);
    this.status = 0; this.latch = false; this.first = 0; this.addr = 0; this.buf = 0;
    this.screen = new Uint8Array(256 * 192);
  }
  writeData(v) { this.vram[this.addr] = v; this.buf = v; this.addr = (this.addr + 1) & 0x3FFF; this.latch = false; }
  readData() { const v = this.buf; this.buf = this.vram[this.addr]; this.addr = (this.addr + 1) & 0x3FFF; this.latch = false; return v; }
  writeCtrl(v) {
    if (!this.latch) { this.first = v; this.latch = true; return; }
    this.latch = false;
    if (v & 0x80) { this.reg[v & 7] = this.first; return; }
    this.addr = ((v & 0x3F) << 8) | this.first;
    if (!(v & 0x40)) { this.buf = this.vram[this.addr]; this.addr = (this.addr + 1) & 0x3FFF; }
  }
  readStatus() { const s = this.status; this.status &= 0x1F; this.latch = false; return s; }
  irq() { return (this.reg[1] & 0x20) !== 0 && (this.status & 0x80) !== 0; }

  render() {
    const r = this.reg, vr = this.vram, out = this.screen;
    const bd = r[7] & 15;
    if (!(r[1] & 0x40)) { out.fill(bd); return; }
    const nt = (r[2] & 0x0F) << 10;
    const g2 = (r[0] & 0x02) !== 0;
    const ct = g2 ? (r[3] & 0x80) << 6 : r[3] << 6;
    const pg = g2 ? (r[4] & 0x04) << 11 : (r[4] & 7) << 11;
    const cmask = ((r[3] & 0x7F) << 3) | 7, pmask = ((r[4] & 3) << 8) | 0xFF;
    for (let row = 0; row < 24; row++) {
      for (let col = 0; col < 32; col++) {
        const n = vr[nt + row * 32 + col];
        let pa, ca;
        if (g2) { const idx = ((row >> 3) << 8) | n; pa = pg + (idx & pmask) * 8; ca = ct + (idx & cmask) * 8; }
        else { pa = pg + n * 8; ca = -1; }
        for (let line = 0; line < 8; line++) {
          const pat = vr[pa + line];
          const cb = ca >= 0 ? vr[ca + line] : vr[ct + (n >> 3)];
          const fg = (cb >> 4) || bd, bg = (cb & 15) || bd;
          const o = (row * 8 + line) * 256 + col * 8;
          for (let b = 0; b < 8; b++) out[o + b] = (pat & (0x80 >> b)) ? fg : bg;
        }
      }
    }
    // sprites: 4 per line, the lowest number has priority
    const sat = (r[5] & 0x7F) << 7, spg = (r[6] & 7) << 11;
    const big = (r[1] & 2) !== 0, mag = (r[1] & 1) ? 2 : 1;
    const size = (big ? 16 : 8) * mag;
    const used = new Uint8Array(256);
    for (let y = 0; y < 192; y++) {
      used.fill(0);
      let count = 0;
      for (let s = 0; s < 32; s++) {
        const sy = vr[sat + s * 4];
        if (sy === 0xD0) break;
        const top = sy >= 0xE1 ? sy - 255 : sy + 1;
        if (y < top || y >= top + size) continue;
        if (++count > 4) { if (!(this.status & 0x40)) this.status = (this.status & 0xE0) | 0x40 | s; break; }
        let sx = vr[sat + s * 4 + 1];
        let name = vr[sat + s * 4 + 2];
        const attr = vr[sat + s * 4 + 3];
        if (attr & 0x80) sx -= 32;
        const color = attr & 15;
        if (big) name &= 0xFC;
        const line = ((y - top) / mag) | 0;
        const w = big ? 16 : 8;
        for (let px = 0; px < w; px++) {
          const byte = vr[spg + name * 8 + (px >= 8 ? 16 : 0) + line];
          if (!(byte & (0x80 >> (px & 7)))) continue;
          for (let m = 0; m < mag; m++) {
            const x = sx + px * mag + m;
            if (x < 0 || x > 255) continue;
            if (used[x]) { this.status |= 0x20; continue; }
            used[x] = 1;
            if (color) out[y * 256 + x] = color;
          }
        }
      }
    }
  }

  png(scale = 2) {
    const w = 256 * scale, h = 192 * scale;
    const raw = Buffer.alloc((w * 3 + 1) * h);
    let o = 0;
    for (let y = 0; y < h; y++) {
      raw[o++] = 0;
      const sy = (y / scale) | 0;
      for (let x = 0; x < w; x++) {
        const c = PALETTE[this.screen[sy * 256 + ((x / scale) | 0)]];
        raw[o++] = c[0]; raw[o++] = c[1]; raw[o++] = c[2];
      }
    }
    const chunk = (type, data) => {
      const len = Buffer.alloc(4); len.writeUInt32BE(data.length);
      const td = Buffer.concat([Buffer.from(type), data]);
      const crc = Buffer.alloc(4); crc.writeUInt32BE(zlib.crc32(td) >>> 0);
      return Buffer.concat([len, td, crc]);
    };
    const ihdr = Buffer.alloc(13);
    ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4);
    ihdr[8] = 8; ihdr[9] = 2; ihdr[10] = 0; ihdr[11] = 0; ihdr[12] = 0;
    return Buffer.concat([
      Buffer.from([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]),
      chunk('IHDR', ihdr), chunk('IDAT', zlib.deflateSync(raw)), chunk('IEND', Buffer.alloc(0)),
    ]);
  }
}

// ---------------- whole machine ----------------
class MiniVIC {
  constructor(bin, loadAddr = 0x0FD0, start = 0x1000) {
    this.mem = new Uint8Array(0x10000);
    this.mem.set(bin, loadAddr);
    // stub of the NMI handler of the BIOS
    const stub = [0x48, 0xDA, 0x5A, 0x20, 0xD0, 0x0F, 0xAD, 0x01, 0xB0, 0x7A, 0xFA, 0x68, 0x40];
    this.mem.set(stub, 0xFF00);
    this.mem[0xFF20] = 0x40;                                   // RTI for IRQ/BRK
    this.mem[0xFFFA] = 0x00; this.mem[0xFFFB] = 0xFF;
    this.mem[0xFFFE] = 0x20; this.mem[0xFFFF] = 0xFF;
    this.vdp = new VDP();
    this.joy = [0, 0];                                         // bit set = pressed (P1, P2)
    this.cpu = new CPU(this);
    this.cpu.pc = start;
    this.frame = 0;
    this.lastIrq = false;
  }
  read(a) {
    if (a === 0xB000) return this.vdp.readData();
    if (a === 0xB001) return this.vdp.readStatus();
    if (a === 0xD581) return (~this.joy[0]) & 0xFF;
    if (a === 0xD580) return (~this.joy[1]) & 0xFF;
    return this.mem[a];
  }
  write(a, v) {
    if (a === 0xB000) return this.vdp.writeData(v);
    if (a === 0xB001) return this.vdp.writeCtrl(v);
    if (a >= 0xD380 && a <= 0xD385) return;                    // AY: no audio
    if (a >= 0xD580 && a <= 0xD583) return;                    // VIA: DDR
    if (a < 0x8000) this.mem[a] = v;
  }
  checkNmi() {
    const irq = this.vdp.irq();
    if (irq && !this.lastIrq) this.cpu.nmi();
    this.lastIrq = irq;
  }
  runFrame() {
    const cpu = this.cpu;
    const end = cpu.cycles + CYCLES_PER_FRAME;
    while (cpu.cycles < end) {
      cpu.step();
      this.checkNmi();
      if (cpu.bad) throw new Error(`unknown opcode $${cpu.bad.opc.toString(16)} at $${cpu.bad.pc.toString(16)}`);
    }
    this.vdp.render();                                         // start of the vblank
    this.vdp.status |= 0x80;
    this.checkNmi();
    this.frame++;
  }
}

module.exports = { MiniVIC };
