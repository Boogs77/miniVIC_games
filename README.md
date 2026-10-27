# miniVIC Games: 65C02 Arcade Collection

A collection of arcade games written in **65C02 assembly** for the **Boogs77-miniVIC**, a compact 8-bit computer built on the modular architecture of the [BO6502 System](https://github.com/Boogs77/BO6502_65C02-based_modular_computer). Every title uses the **TMS9918A** video processor for tile and sprite graphics and two **AY-3-8910** sound chips for stereo music and effects.

> 🚧 The **miniVIC** hardware project (schematics, enclosure, firmware) will be published in its own repository: [miniVIC_65c02](https://github.com/Boogs77/miniVIC_65c02) (coming soon). This repository contains only the game software.

---

## 🎮 Games

| File | Game | Players | Description |
| :--- | :--- | :---: | :--- |
| `tank.asm` | **Tank vs Tank** | 1–2 | Two tanks on a green battlefield: rotate, move and shoot. First to reach the winning score wins. Play against a friend or against the computer. |
| `1vs1.asm` | **1 vs 1 Basketball** | 1–2 | One-on-one basketball with shots, jumps, steals and blocks. 2 and 3 point shots, first to 21 wins. Play against a friend or against the computer. |
| `centipede.asm` | **Centipede** | 1 | The classic arcade: shoot the centipede through the mushroom field, watch out for the flea and the spider. Infinite levels. |
| `missile_command.asm` | **Missile Command** | 1–2 | Defend 6 cities from incoming missiles using 3 bases. The second player can join at any time. Full bitmap graphics. |
| `lunar_lander.asm` | **Lunar Lander** | 1 | Land the module softly on the moon pads: smaller pads pay more, plus a leftover fuel bonus. 6 moon maps, 3 landers. Full bitmap graphics. |
| `the_warriors.asm` | **The Warriors** | 1–2 | Street Fighter style fighting game: 5 warriors, 6 stages, punch, kick, block and special move. Best of 3 rounds. Play against a friend or against the computer. |
| `breakout.asm` | **Breakout** | 1–2 | Atari 1976: 8 rows of bricks in four colours, the ball speeds up and the paddle shrinks when you break through. Two walls, players take turns. |
| `asteroids.asm` | **Asteroids** | 1–2 | Atari 1979: vector-style asteroids that split in three sizes, large and small saucers, hyperspace and the famous heartbeat. Players take turns. |
| `space_invaders.asm` | **Space Invaders** | 1–2 | Taito 1978: 55 invaders that march one at a time, shields that crumble pixel by pixel, three kinds of bombs, mystery saucer and the four-note march. Colour bands of the cabinet overlay. |
| `warlords.asm` | **Warlords** | 1–2 | Atari 1980: four castles, shields on an L-shaped track, catch and throw the fireball. 1 or 2 players against the computer castles; first to 3 rounds wins. |
| `defender.asm` | **Defender** | 1 | Williams 1981: a scrolling planet that wraps around, scanner, landers kidnapping humanoids, mutants, bombers, pods, swarmers and baiters; laser, smart bombs, hyperspace. |
| `radar_scope.asm` | **Radar Scope** | 1–2 | Nintendo 1980: a field in perspective with a blue sky and a curved radar grid, 48 Gamma Raiders that hover forward, dive and drop decoys, and a damage meter that slows down the laser. Players take turns. |
| `space_firebird.asm` | **Space Firebird** | 1–2 | Nintendo 1980: a scrolling starfield, Firebirds that arrive as comets, loop the loop and turn into Gulls, Eagles and Emperors; eagle bombs that burst into shrapnel, a once-per-ship shielded warp and a PERFECT bonus for 50 birds out of 50. Players take turns. |
| `moon_cresta.asm` | **Moon Cresta** | 1–2 | Nichibutsu 1980: a three-stage rocket where every stage is a life, timed docking with retro rockets for a bonus and more firepower, and waves of Cold Eyes that split in two, Super Flies, Four-Ds, meteors and Atomic Piles, with a start tune. Players take turns. |
| `stargate.asm` | **Stargate** | 1–2 | Williams 1981, the sequel to Defender: the Stargate that jumps to the humanoid in danger (or warps 3 waves ahead with 4 humanoids on board), Inviso cloaking, several humanoids carried at once, Firebombers, Yllabian Space Guppies, Dynamos, Phreds and Big Reds, plus the Yllabian Dogfight and Firebomber Showdown waves. Players take turns. |
| `gravitar.asm` | **Gravitar** | 1–2 | Atari 1982: fly from planet to planet of 3 solar systems while the death star pulls the ship in, blast the bunkers, pull up fuel cells with the tractor beam, raise the shield, fight the alien saucer in deep space and blow up the reactor of the red planet before the clock runs out. Then the universe changes: negative gravity, invisible landscape, both. Players take turns. |
| `quantum.asm` | **Quantum** | 1–2 | Atari 1982: guide your probe with inertia like a trackball to draw loops around particles and destroy them. Multiple particles in one loop multiply the score. Progressively harder waves with nuclei that release positrons, splitters that divide and pulsars that hunt. Players take turns. |
| `joust.asm` | **Joust** | 1–2 | Williams 1982: a knight on a flying ostrich, and a second one on a stork with both players at the same time. Flap to climb: the higher lance wins. Bounders, Hunters and Shadow Lords leave eggs to pick up before they hatch, the pterodactyl must be hit in the beak, the hand of the troll grabs who flies low over the lava and the bridge burns away. Survival, Team, Gladiator and Egg waves. |
| `exerion.asm` | **Exerion** | 1–2 | Jaleco 1983: a fighter with inertia over a planet whose ground rushes towards you in pseudo-3D bands, with the landscape on the horizon moving in parallax. Formations of amoebae, egg-throwing birds, pterosaurs and UFOs come from the horizon, growing as they approach, then dive or swoop away. Unlimited dual shot, rapid single shot that uses charges (won back by hitting with the dual shot), formation bonus doubling up to 10000 and a challenging stage after every stage. Players take turns. |
| `bubbles.asm` | **Bubbles** | 1–2 | Williams 1982: a soap bubble cleans a kitchen sink, sliding with inertia and growing as it eats crumbs, ants and grease (double near the drain). With eyes and a mouth it bounces sponges and brushes away, even down the drain; razor blades always pop it. Take the broom from the cleaning lady's bristles to swat the roaches that crawl out of the red-flashing drain, then slip into the green drain for a bonus of 1000 times your size before the last dirt is gone and the faucet runs. 99 levels, players take turns. |
| `times_tables.asm` | **Times Tables** | 1–2 | An original educational game (screen texts in Italian, *TABELLINE*): the times tables from 1 to 10, one question and four answers in a cross, chosen with one push of the joystick. Practice with help, a challenge with a red two-digit countdown like a basketball scoreboard, and a duel against a friend or the computer. Wrong answers show the repeated sum and come back more often; a colour table shows what has been learnt, and every table has a monster to catch and evolve. |

Each source file starts with a header describing controls, rules and technical notes.

> ℹ️ These games are non-commercial fan-made tributes to the original arcade games: see the **Disclaimer** at the end of this page.

---

## 🧠 Hardware Requirements

The games run on the miniVIC and rely on the following BO6502 modules:

### 📺 Video (TMS9918A)
* **Mode:** Graphics II (256x192, 32 sprites), bitmap mode for Missile Command.
* **Addressing:** VDP register port at **$B001**.
* **Reference:** [BO6502 VDU](https://github.com/Boogs77/BO6502_65C02-based_modular_computer/tree/main/BO6502%20VDU).

### 🔊 Audio (2 x AY-3-8910)
* **Right channel:** latch **$D380**, write **$D381**.
* **Left channel:** latch **$D384**, write **$D385**.
* **Reference:** [BO6502 AUDIO](https://github.com/Boogs77/BO6502_65C02-based_modular_computer/tree/main/BO6502%20AUDIO).

### 🕹️ Joysticks (W65C22 VIA)
* **Player 1:** PORTA at **$D581**.
* **Player 2:** PORTB at **$D580**.
* **Bits:** UP, DOWN, LEFT, RIGHT, button 1 (bit4), button 2 (bit5).
* **Reference:** [BO6502 JOYSTICK](https://github.com/Boogs77/BO6502_65C02-based_modular_computer/tree/main/BO6502%20JOYSTICK).

---

## 💻 Program Structure

All games share the same layout:
* **Load address:** programs are assembled at **$1000**.
* **NMI trampoline:** at **$0FD0**, called by the BIOS `NMI_HANDLER` with `JSR $0FD0` on every VDP vertical blank (60 Hz).
* **Frame update:** the NMI copies the sprite attribute table (SAT) buffer to the VDP and runs the sound engine, while the main loop handles game logic.
* **Graphics data:** screens, patterns and sprites are stored as generated tables at the bottom of each file.

---

## 🛠️ Build

The games are assembled with **vasm6502_oldstyle** (`-Fbin -dotdir -c02`). Ready-to-load binaries are in the [`bin`](bin) folder; each one starts at **$0FD0** (NMI trampoline) followed by the program at **$1000**.

To rebuild them:
1. Write the full path of `vasm6502_oldstyle.exe` in a file named `vasm.path` (or set the `VASM` environment variable).
2. Run `build.bat` to assemble all games, or `build.bat tank.asm` for a single one. In VS Code, press **Ctrl+Shift+B** to build the open file.

The script assembles every file into `bin/`, optionally copies the sources and binaries to the local folder written in `copy.path`, runs each game in the emulator to update its screenshots, then commits and pushes the updated binaries and screenshots. Use `build.ps1 -NoPublish` to build without publishing.

### 🖥️ Emulator & Screenshots
The [`tools`](tools) folder contains a small **miniVIC emulator** written in Node.js (no dependencies): W65C02S CPU, TMS9918A video with sprites, VDP interrupt on NMI and the two joysticks. It has no audio, but it can record what the games write to the two AY chips.
* `node tools/screenshots.js` runs every game and saves its screenshots in [`screenshots`](screenshots).
* `tools/screenshots.json` defines, for each game, the input sequence (wait, button presses, random play) and when to take each picture.
* `node tools/aywav.js tank` runs a game, records its AY writes and renders them to a stereo WAV in `sounds/` (left AY = left channel), to listen to the music and sound effects without the hardware.

---

## 🖼️ Screenshots

Captured with the miniVIC emulator in [`tools`](tools): title screen and gameplay.

### Tank vs Tank
<p align="center">
  <img src="screenshots/tank_title.png" width="45%" />
  <img src="screenshots/tank_game.png" width="45%" />
</p>

### 1 vs 1 Basketball
<p align="center">
  <img src="screenshots/1vs1_title.png" width="45%" />
  <img src="screenshots/1vs1_game.png" width="45%" />
</p>

### Centipede
<p align="center">
  <img src="screenshots/centipede_title.png" width="45%" />
  <img src="screenshots/centipede_game.png" width="45%" />
</p>

### Missile Command
<p align="center">
  <img src="screenshots/missile_command_title.png" width="45%" />
  <img src="screenshots/missile_command_game.png" width="45%" />
</p>

### Lunar Lander
<p align="center">
  <img src="screenshots/lunar_lander_title.png" width="45%" />
  <img src="screenshots/lunar_lander_game.png" width="45%" />
</p>

### The Warriors
<p align="center">
  <img src="screenshots/the_warriors_title.png" width="45%" />
  <img src="screenshots/the_warriors_game.png" width="45%" />
</p>

### Breakout
<p align="center">
  <img src="screenshots/breakout_title.png" width="45%" />
  <img src="screenshots/breakout_game.png" width="45%" />
</p>

### Asteroids
<p align="center">
  <img src="screenshots/asteroids_title.png" width="45%" />
  <img src="screenshots/asteroids_game.png" width="45%" />
</p>

### Space Invaders
<p align="center">
  <img src="screenshots/space_invaders_title.png" width="45%" />
  <img src="screenshots/space_invaders_game.png" width="45%" />
</p>

### Warlords
<p align="center">
  <img src="screenshots/warlords_title.png" width="45%" />
  <img src="screenshots/warlords_game.png" width="45%" />
</p>

### Defender
<p align="center">
  <img src="screenshots/defender_title.png" width="45%" />
  <img src="screenshots/defender_game.png" width="45%" />
</p>

### Radar Scope
<p align="center">
  <img src="screenshots/radar_scope_title.png" width="45%" />
  <img src="screenshots/radar_scope_game.png" width="45%" />
</p>

### Space Firebird
<p align="center">
  <img src="screenshots/space_firebird_title.png" width="45%" />
  <img src="screenshots/space_firebird_game.png" width="45%" />
</p>

### Moon Cresta
<p align="center">
  <img src="screenshots/moon_cresta_title.png" width="45%" />
  <img src="screenshots/moon_cresta_game.png" width="45%" />
</p>

### Stargate
<p align="center">
  <img src="screenshots/stargate_title.png" width="45%" />
  <img src="screenshots/stargate_game.png" width="45%" />
</p>

### Gravitar
<p align="center">
  <img src="screenshots/gravitar_title.png" width="45%" />
  <img src="screenshots/gravitar_game.png" width="45%" />
</p>

### Quantum
<p align="center">
  <img src="screenshots/quantum_title.png" width="45%" />
  <img src="screenshots/quantum_game.png" width="45%" />
</p>

### Joust
<p align="center">
  <img src="screenshots/joust_title.png" width="45%" />
  <img src="screenshots/joust_game.png" width="45%" />
</p>

### Exerion
<p align="center">
  <img src="screenshots/exerion_title.png" width="45%" />
  <img src="screenshots/exerion_game.png" width="45%" />
</p>

### Bubbles
<p align="center">
  <img src="screenshots/bubbles_title.png" width="45%" />
  <img src="screenshots/bubbles_game.png" width="45%" />
</p>

### Times Tables
<p align="center">
  <img src="screenshots/times_tables_title.png" width="45%" />
  <img src="screenshots/times_tables_game.png" width="45%" />
</p>

---

## 🔗 Useful Links & Resources

* **BO6502 System:** [65C02-based Modular Computer](https://github.com/Boogs77/BO6502_65C02-based_modular_computer)
* **miniVIC:** [miniVIC 65C02 hardware project](https://github.com/Boogs77/miniVIC_65c02) (coming soon)
* **miniPET:** [The sister project, miniPET 65C02](https://github.com/Boogs77/miniPET_65c02)
* **Video Module:** [BO6502 VDU Reference](https://github.com/Boogs77/BO6502_65C02-based_modular_computer/tree/main/BO6502%20VDU)
* **Audio Module:** [BO6502 AUDIO Reference](https://github.com/Boogs77/BO6502_65C02-based_modular_computer/tree/main/BO6502%20AUDIO)
* **Joystick Module:** [BO6502 JOYSTICK Reference](https://github.com/Boogs77/BO6502_65C02-based_modular_computer/tree/main/BO6502%20JOYSTICK)

---

## ⚖️ Disclaimer

The games in this repository are **fan-made tributes** to classic arcade games. They were written from scratch in 65C02 assembly for the miniVIC as a **non-commercial, educational and demonstration project**, to show what this home-built hardware can do.

* All titles, characters, artwork, sounds and trademarks of the original games (such as *Asteroids*, *Breakout*, *Bubbles*, *Centipede*, *Defender*, *Exerion*, *Gravitar*, *Joust*, *Lunar Lander*, *Missile Command*, *Moon Cresta*, *Quantum*, *Radar Scope*, *Space Firebird*, *Space Invaders*, *Stargate* and *Warlords*) belong to their **respective owners**. Their names are used only to identify the games that inspired these versions.
* This project is **not affiliated with, endorsed or sponsored by** any of the rights holders, and claims no rights over the original games.
* No original program code or ROM data has been used: graphics and sounds are new re-creations made to resemble the originals.
* No commercial use is intended. If you are a rights holder and have any concern, please [open an issue](https://github.com/Boogs77/miniVIC_games/issues) and the material will be reviewed or removed promptly.

---
*Created by Boogs77 - 2026*
