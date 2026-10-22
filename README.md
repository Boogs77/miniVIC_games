# MiniVIC Games

Giochi arcade scritti in assembly 65C02 per un computer homebrew con
VDP TMS9918A (Graphics II) e due chip audio AY-3-8910.

Ogni gioco si carica a `$1000`, con un trampolino a `$0FD0` chiamato
dall'NMI del BIOS (vblank). I joystick sono letti dalla VIA:
P1 su PORTA `$D581`, P2 su PORTB `$D580`.

| File | Gioco |
|------|-------|
| `tank.asm` | Tank vs Tank, 2 giocatori |
| `1vs1.asm` | Basket 1 contro 1 |
| `centipede.asm` | Centipede |
| `arcade_missile_command.asm` | Missile Command, 1-2 giocatori |
| `the_warriors.asm` | The Warriors, picchiaduro 1 contro 1 |

I dettagli di comandi e regole sono nell'intestazione di ogni file.
