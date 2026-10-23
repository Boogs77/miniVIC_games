'use strict';
// aywav.js - runs a game in the emulator, records the writes to the two AY-3-8910
// and renders them to a stereo WAV (left AY = left channel, right AY = right channel)
//
//   node tools/aywav.js tank                     bin/tank.bin, 25 s, sounds/tank.wav
//   node tools/aywav.js tank 10                  only the first 10 seconds
//   node tools/aywav.js song.bin 12 out.wav 1000 a .bin file loaded and started at $1000
//
// Arguments: <game or .bin> [seconds] [out.wav] [load address hex] [start address hex]
// Defaults: load $0FD0, start $1000 (the games); a program that jumps to the BIOS
// ($E000-$FEFF) stops the recording there.
// AY clock 1 MHz; no envelopes (the games do not use them); approximate volumes.

const fs = require('fs');
const path = require('path');
const { MiniVIC } = require('./minivic');

const ROOT = path.join(__dirname, '..');
const CLK = 1000000, SR = 44100;
const VOL = [0, .0106, .015, .0222, .0326, .0472, .0767, .1, .158, .224, .343, .414, .59, .719, .858, 1];

const [arg, secArg, outArg, loadArg, startArg] = process.argv.slice(2);
if (!arg) { console.log('usage: node tools/aywav.js <game or .bin> [seconds] [out.wav] [load hex] [start hex]'); process.exit(1); }
const isBin = arg.toLowerCase().endsWith('.bin');
const binPath = isBin ? arg : path.join(ROOT, 'bin', `${arg}.bin`);
const name = path.basename(binPath, '.bin');
const seconds = Number(secArg) || 25;
const out = outArg || path.join(ROOT, 'sounds', `${name}.wav`);

// ---------------- recording ----------------
const m = new MiniVIC(fs.readFileSync(binPath), parseInt(loadArg || '0FD0', 16), parseInt(startArg || '1000', 16));
const ev = [];                                   // [cycle, chip, register, value]; chip 0 = left
const latch = [0, 0];
const write = m.write.bind(m);
m.write = (a, v) => {
  if (a === 0xD384) latch[0] = v & 15;
  else if (a === 0xD380) latch[1] = v & 15;
  else if (a === 0xD385) ev.push([m.cpu.cycles, 0, latch[0], v]);
  else if (a === 0xD381) ev.push([m.cpu.cycles, 1, latch[1], v]);
  write(a, v);
};
const inBios = () => m.cpu.pc >= 0xE000 && m.cpu.pc < 0xFF00;   // $FF00 = NMI stub
try {
  for (let i = 0; i < seconds * 60 && !inBios(); i++) m.runFrame();
} catch (e) {
  if (!inBios()) throw e;                        // the BIOS is not emulated: end of the program
}

// ---------------- AY synthesis ----------------
const N = Math.floor(m.cpu.cycles / CLK * SR);
const buf = Buffer.alloc(44 + N * 4);
const chips = [0, 1].map(() => ({ r: new Uint8Array(16).fill(0), ph: [0, 0, 0], out: [0, 0, 0], nph: 0, lfsr: 1, nout: 0 }));
chips.forEach(c => { c.r[7] = 0xFF; });
const step = CLK / SR / 8;                       // tone outputs flip every period * 8 clocks
let ei = 0;
for (let s = 0; s < N; s++) {
  const cyc = s * CLK / SR;
  while (ei < ev.length && ev[ei][0] <= cyc) { const [, ch, rg, v] = ev[ei++]; chips[ch].r[rg] = v; }
  chips.forEach((c, ci) => {
    const np = (c.r[6] & 31) || 1;
    c.nph += step;
    while (c.nph >= np) {                        // 17-bit LFSR noise
      c.nph -= np;
      const b = (c.lfsr ^ (c.lfsr >> 3)) & 1;
      c.lfsr = (c.lfsr >> 1) | (b << 16);
      c.nout = c.lfsr & 1;
    }
    let sum = 0;
    for (let k = 0; k < 3; k++) {
      const tp = (c.r[k * 2] | ((c.r[k * 2 + 1] & 15) << 8)) || 1;
      c.ph[k] += step;
      while (c.ph[k] >= tp) { c.ph[k] -= tp; c.out[k] ^= 1; }
      const toneOn = !(c.r[7] & (1 << k)), noiseOn = !(c.r[7] & (8 << k));
      if (!toneOn && !noiseOn) continue;
      const bit = (toneOn ? c.out[k] : 1) & (noiseOn ? c.nout : 1);
      sum += bit * VOL[c.r[8 + k] & 15];
    }
    buf.writeInt16LE(Math.round((sum / 3 - .15) * 26000), 44 + s * 4 + ci * 2);
  });
}

// ---------------- WAV file ----------------
buf.write('RIFF', 0); buf.writeUInt32LE(36 + N * 4, 4); buf.write('WAVEfmt ', 8);
buf.writeUInt32LE(16, 16); buf.writeUInt16LE(1, 20); buf.writeUInt16LE(2, 22);
buf.writeUInt32LE(SR, 24); buf.writeUInt32LE(SR * 4, 28); buf.writeUInt16LE(4, 32); buf.writeUInt16LE(16, 34);
buf.write('data', 36); buf.writeUInt32LE(N * 4, 40);
fs.mkdirSync(path.dirname(out), { recursive: true });
fs.writeFileSync(out, buf);
console.log(`${name}: ${out} (${(m.cpu.cycles / CLK).toFixed(1)} s, ${ev.length} AY writes)`);
