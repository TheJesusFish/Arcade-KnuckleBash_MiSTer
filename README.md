# Knuckle Bash MiSTer Core

This is a vibe coded, MAME-based Knuckle Bash arcade core for the MiSTer FPGA, implementing Toaplan's 1993 TP-023 hardware.
It builds on the excellent Toaplan scaffolding and GP9001 reference work from [Erin Olafsen](https://github.com/va7deo) and [Pramod Somashakar](https://github.com/psomashekar), through the [Batsugun core](https://github.com/TheJesusFish/Arcade-Batsugun_MiSTer) and local Dogyuun development work.

## Hardware Reference

MAME models Knuckle Bash as:

- Motorola 68000 main CPU at 16 MHz.
- Encrypted NEC V25 audio/control CPU at 16 MHz, with Nitro opcode decryption.
- One GP9001 video device clocked from 27 MHz.
- YM2151 at 27 MHz / 8 (3.375 MHz).
- OKIM6295 at 1 MHz, pin 7 high.
- Raster timing: 27 MHz / 4 pixel clock, 432 total horizontal clocks, 320 visible pixels, 262 total lines, 240 visible lines; native horizontal orientation, approximately 59.6374 Hz.

## Source Notes

- MiSTer framework and top-level structure:
  [MiSTer-devel/Main_MiSTer](https://github.com/MiSTer-devel/Main_MiSTer) and
  [Jotego jtcores / JTFrame](https://github.com/jotego/jtcores/tree/master/modules/jtframe)

- MC68000-compatible CPU core:
  [ijor/fx68k](https://github.com/ijor/fx68k)

- YM2151-compatible sound core:
  [ika-musume IKAOPM](https://github.com/ika-musume/IKAOPM), with the pinned revision in
  [UPSTREAM.md](rtl/modules/ikaopm/UPSTREAM.md)

- OKIM6295-compatible ADPCM sound core:
  [Jotego jt6295](https://github.com/jotego/jtcores/tree/master/modules/jt6295), with a separately attributed Knuckle Bash-local inclusive-end wrapper.

- NEC V25 core:
  Local compact implementation derived from [nand2mario/z8086](https://github.com/nand2mario/z8086), with Batsugun/Dogyuun adaptations and Knuckle Bash-specific integration. See the retained [provenance and microcode notice](rtl/modules/v25_compact/UPSTREAM.md).

- Save-state architecture references:
  [WickerWaka](https://github.com/wickerwaka)'s Taito F2 and PGM work. 

- Behavioral references:
  [MAME 0.288 Toaplan `kbash.cpp`](https://github.com/mamedev/mame/blob/mame0288/src/mame/toaplan/kbash.cpp),
  [MAME Toaplan `gp9001.cpp`](https://github.com/mamedev/mame/blob/mame0288/src/mame/toaplan/gp9001.cpp), and
  [MAME Toaplan `gp9001.h`](https://github.com/mamedev/mame/blob/mame0288/src/mame/toaplan/gp9001.h)

Build with Quartus Prime Lite 17.0.2 and Cyclone V support: open `Arcade-KnuckleBash.qpf`, or run `quartus_sh --flow compile Arcade-KnuckleBash`. The target is `5CSEBA6U23I7`; all required HDL/IP and initialization files are included. Rename `output_files/Arcade-KnuckleBash.rbf` to `KnuckleBash.rbf` and place it in your arcade MRA folder's `cores/` subfolder. Use the included MRAs with your own MAME 0.288-compatible ROM sets in `games/mame/`.

Original copyright, license, and upstream provenance notices are retained. Local research, tests, captures, restore snapshots, and generated output are preserved on disk but excluded from the public source package by `.gitignore`.
