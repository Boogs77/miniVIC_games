'use strict';
// screenshots.js - fa girare i giochi nell'emulatore e salva gli screenshot
//
//   node tools/screenshots.js              tutti i giochi di screenshots.json
//   node tools/screenshots.js tank 1vs1    solo quelli indicati
//
// Per ogni gioco screenshots.json elenca dei passi:
//   ["wait", n]               n frame senza toccare niente
//   ["press", "p1", "fire", n] tiene premuto per n frame, poi rilascia (p1 / p2 / both)
//   ["mash", n]               per n frame preme il tasto 1 di entrambi ogni mezzo secondo
//                             (supera titoli con musica e schermate di selezione)
//   ["play", n]               n frame di gioco con joystick casuali (entrambi i giocatori)
//   ["shot", "nome"]          salva screenshots/<gioco>_<nome>.png
// Comandi: up down left right fire fire2 (combinabili con "+", es. "right+fire")
// Un gioco che non compare nel file usa la sequenza "_default".

const fs = require('fs');
const path = require('path');
const { MiniVIC } = require('./minivic');

const ROOT = path.join(__dirname, '..');
const BITS = { up: 1, down: 2, left: 4, right: 8, fire: 16, fire2: 32 };

function bits(spec) {
  return spec.split('+').reduce((v, k) => {
    if (!(k in BITS)) throw new Error(`comando sconosciuto: ${k}`);
    return v | BITS[k];
  }, 0);
}

function rng(seed) {                         // generatore deterministico (stessi screenshot a ogni giro)
  let s = seed >>> 0;
  return () => { s = (s * 1664525 + 1013904223) >>> 0; return s / 4294967296; };
}

function runGame(name, steps, outDir) {
  const bin = fs.readFileSync(path.join(ROOT, 'bin', `${name}.bin`));
  const m = new MiniVIC(bin);
  const rand = rng(1234);
  const hold = [0, 0], timer = [0, 0];
  const randomJoy = () => {
    for (let p = 0; p < 2; p++) {
      if (--timer[p] > 0) continue;
      timer[p] = 8 + Math.floor(rand() * 25);
      const dirs = [0, 1, 2, 4, 8, 5, 9, 6, 10];
      hold[p] = dirs[Math.floor(rand() * dirs.length)] | (rand() < 0.5 ? 16 : 0) | (rand() < 0.2 ? 32 : 0);
    }
    m.joy[0] = hold[0]; m.joy[1] = hold[1];
  };
  const saved = [];
  for (const [cmd, a, b, c] of steps) {
    if (cmd === 'wait') { m.joy = [0, 0]; for (let i = 0; i < a; i++) m.runFrame(); }
    else if (cmd === 'press') {
      const v = bits(b);
      m.joy = [a !== 'p2' ? v : 0, a !== 'p1' ? v : 0];
      for (let i = 0; i < (c || 6); i++) m.runFrame();
      m.joy = [0, 0];
      for (let i = 0; i < 6; i++) m.runFrame();
    }
    else if (cmd === 'mash') {
      for (let i = 0; i < a; i++) { m.joy = (i % 30) < 6 ? [16, 16] : [0, 0]; m.runFrame(); }
      m.joy = [0, 0];
    }
    else if (cmd === 'play') { for (let i = 0; i < a; i++) { randomJoy(); m.runFrame(); } m.joy = [0, 0]; }
    else if (cmd === 'shot') {
      const file = path.join(outDir, `${name}_${a}.png`);
      fs.writeFileSync(file, m.vdp.png(2));
      saved.push(path.relative(ROOT, file));
    }
    else throw new Error(`passo sconosciuto: ${cmd}`);
  }
  return saved;
}

const config = JSON.parse(fs.readFileSync(path.join(__dirname, 'screenshots.json'), 'utf8'));
const outDir = path.join(ROOT, 'screenshots');
fs.mkdirSync(outDir, { recursive: true });
const games = process.argv.slice(2).length ? process.argv.slice(2) : Object.keys(config).filter(g => g !== '_default');
let failed = 0;
for (const g of games) {
  try {
    const t = Date.now();
    const files = runGame(g, config[g] || config._default, outDir);
    console.log(`${g}: ${files.join(', ')} (${((Date.now() - t) / 1000).toFixed(1)} s)`);
  } catch (e) {
    console.error(`${g}: ERRORE ${e.message}`);
    failed++;
  }
}
process.exit(failed ? 1 : 0);
