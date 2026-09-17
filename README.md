6502-CRT
========

A 6502 assembly language cartridge template for the [AC6502](https://github.com/acwright/6502-ACE) family of computer systems.

> 📖 **Guide:** [AC6502 Documentation](https://acwright.github.io/6502-DOCS/) — the user's and programmer's guide for the whole family.
> This template is walked through end to end in [Writing a cartridge](https://acwright.github.io/6502-DOCS/assembly/cartridges).

## Overview

Cartridges for this system overlay the ROM address space from `$C000–$FFFF`, replacing the BASIC interpreter, Wozmon, the CPU vectors and, on BIOS 1.x, the Monitor with custom code. The Kernal remains accessible underneath — `$A000–$B7FF` plus the character set at `$B800–$BFFF` on BIOS 1.x, all of `$A000–$BFFF` on BIOS 2.x — providing hardware initialization, character I/O, video, sound, storage, and other system services through a stable jump table.

The template builds two ways from the same source: `make` for any ACE on BIOS 1.x with a TMS9918A, and `make VDP=1` for an ACE converted to a [6502-PICOVDP](https://github.com/acwright/6502-PICOVDP) on BIOS 2.x. See [Building for the 6502-PICOVDP](#building-for-the-6502-picovdp).

### How It Works

1. The cartridge ROM physically overrides the BIOS ROM in the `$C000–$FFFF` range
2. The CPU fetches the RESET vector from `$FFFC–$FFFD` — now supplied by the cartridge
3. The cartridge's reset handler calls `KernalInit` (`$A078`) to initialize all hardware
4. After init, the cartridge takes full control — display its own UI, run its program, etc.

### Memory Layout

| Range | Contents |
|-------|----------|
| `$0000–$7FFF` | RAM (32 KB — zero page, stack, input buffer, variables, program space) |
| `$8000–$9FFF` | I/O hardware registers (directly addressable) |
| `$A000–$A0FF` | **Kernal jump table** — stable API entry points (available to cartridges) |
| `$A100–$BFFF` | Kernal implementation (available to cartridges); on BIOS 1.x the character set is at `$B800–$BFFF` |
| `$C000–$FFF9` | **Cartridge ROM** — your code goes here |
| `$FFFA–$FFFF` | **CPU vectors** — NMI, RESET, IRQ (supplied by cartridge) |

### Kernal Services

After calling `KernalInit`, the full Kernal jump table is available. Key entry points:

| Address | Routine | Description |
|---------|---------|-------------|
| `$A078` | `KernalInit` | Initialize all hardware; caller must reset stack pointer first. Returns via RTS (no CLI, no splash) |
| `$A07B` | `KernalVersion` | Get BIOS version (A=major, X=minor) |
| `$A000` | `Chrout` | Output character (routed by IO_MODE) |
| `$A003` | `Chrin` | Read character from input buffer |
| `$A030` | `Beep` | Play startup beep (skips if no SID) |
| `$A018` | `VideoClear` | Clear screen and reset cursor (skips if no video card) |
| `$A01E` | `VideoSetCursor` | Set cursor position (X=col, Y=row; skips if no video card) |
| `$A00F` | `SetIOMode` | Set console output mode (A=0 video, A=1 serial) |

See `6502.inc` for the complete jump table and hardware register definitions. On BIOS 2.x the jump table grew by thirteen PICOVDP entries (`VdpInfo` through `VdpStatus`, `$A0B1–$A0D5`): see Section 4 of `6502-VDP.inc`.

Routines that drive an optional card check `HW_PRESENT` themselves, so calling
one on a machine without that card is safe. Video and sound routines return
silently; storage routines report failure in the carry.

### Interrupt Handling

The cartridge owns the hardware vectors at `$FFFA–$FFFF`. The template uses trampoline routines that jump through the RAM-based vectors (`IRQ_PTR` at `$0300`, `NMI_PTR` at `$0304`) which `KernalInit` sets to the default Kernal handlers. This means:

- **Keyboard input works out of the box** — the default IRQ handler processes keyboard scancodes
- **Custom IRQ handling** — override `IRQ_PTR` after `KernalInit` to install your own handler
- **Direct vectors** — alternatively, point the hardware vector directly at your handler (bypasses the RAM indirection)

### Hardware Detection

After `KernalInit`, read `HW_PRESENT` (`$030D`) to discover installed hardware:

```asm
lda HW_PRESENT
and #HW_VID            ; Is video card present?
beq @NoVideo           ; Skip video-specific code if not
```

On BIOS 2.x, `HW_VID` means a 6502-PICOVDP with its built-in font.

## Building for the 6502-PICOVDP

`make VDP=1` builds `Cart-VDP.crt` with `6502-VDP.inc` instead of `6502.inc`. `Cart.asm` picks the include with the `VDP` symbol, which the Makefile passes to ca65:

```asm
.ifdef VDP
.include "6502-VDP.inc"
.else
.include "6502.inc"
.endif
```

Start from `6502-VDP.inc` when the cartridge needs anything BIOS 2.x adds: the PICOVDP's modes, layers, palette and sprites (`VC_*` register names), or the Kernal's VDP entries. A cartridge built that way needs an ACE converted to a 6502-PICOVDP, running BIOS 2.x, and **does not run on a TMS9918A**. Its build checks `KernalVersion` after `KernalInit` and, on BIOS 1.x, prints `NEEDS BIOS 2 AND A 6502-PICOVDP` and halts.

A cartridge built with `6502.inc` needs no VDP build to run on 2.x. `KernalInit` leaves the PICOVDP in the TMS9918-compatible submode it resets to, and the Text console comes up the first time the cartridge prints, so a legacy cartridge runs unchanged whether it prints through the Kernal or drives the video chip itself.

What is different on BIOS 2.x:

- **The Kernal is all of `$A000–$BFFF`.** There is no character set in ROM and no Monitor.
- **The font is in the card.** A cartridge that overwrote the pattern table gets the text font back with `InitVideo`, which reloads it and restores the Text console, or with `VdpLoadFont` (`A` = `$00`), which loads only the glyphs, into layer 0's pattern table wherever `L0PAT` points. Both return after the next vertical blank.
- **`InitVideo` writes `IRQEN` = 0.** A cartridge using a PICOVDP interrupt enables it again after the console comes up, and after anything that calls `InitVideo`.
- **`BRK_PTR` points at the Kernal's BRK report**, which warm-starts BASIC at `$C000`. A cartridge replaces BASIC, so point `BRK_PTR` at a handler of your own if the cartridge can hit a `BRK`.
- **`VideoSetColor` sets the pen**, the colour of text printed from then on, and the border follows the background.

## Building

### Prerequisites

#### CC65 Compiler

On macOS, install via Homebrew:
```bash
brew install cc65
```

For other platforms, see the [cc65 project](https://github.com/cc65/cc65).

#### Optional: minipro (for EEPROM burning)

```bash
brew install minipro
```

#### Optional: 6502 CLI (for `make run`)

Installed via the [6502-EMULATOR](https://github.com/acwright/6502-EMULATOR) app's Settings → Command Line → Install.

### Build Commands

| Command | Description |
|---------|-------------|
| `make` | Build the cartridge ROM (`Cart.crt`) |
| `make VDP=1` | Build the 6502-PICOVDP / BIOS 2.x version (`Cart-VDP.crt`) |
| `make view` | Display hexdump of the built ROM |
| `make run` | Launch the emulator app with the built cartridge loaded (`make VDP=1 run` selects the PICOVDP card; add `ROM=path/to/BIOS.bin` to boot a local BIOS image) |
| `make eeprom` | Write the ROM to an AT28C256 EEPROM via TL866 programmer |
| `make clean` | Remove build artifacts |

### Build Output

```bash
make
```

Produces:
- `Cart.crt` — 32 KB ROM image (`$8000–$FFFF`), ready to burn to a 28C256 or 27C256 PROM
- `Cart.lst` — Assembly listing file for debugging

`make VDP=1` writes `Cart-VDP.crt` and `Cart-VDP.lst` beside them, and `make VDP=1 eeprom` burns `Cart-VDP.crt`.

### Programming the EEPROM

```bash
make eeprom
```

Burns `Cart.crt` to an AT28C256 EEPROM using a TL866-compatible programmer and minipro.

## Template Structure

| File | Purpose |
|------|---------|
| `Cart.asm` | Main cartridge source — entry point, example code, vectors |
| `6502.inc` | System include file for BIOS 1.x and the TMS9918A — Kernal jump table, hardware registers, constants |
| `6502-VDP.inc` | System include file for BIOS 2.x and the 6502-PICOVDP (identical to 6502-ASM's) |
| `6502.cfg` | Linker configuration — memory layout for cartridge ROM |
| `Makefile` | Build system |

## Customizing

1. Edit `Cart.asm` — replace the example code after `cli` with your program
2. The `CartReset` label is called on power-on; `KernalInit` is already called for you
3. Add additional `.asm` files and `.include` them from `Cart.asm` as needed
4. The cartridge has ~16 KB of ROM space (`$C000–$FFF9`) for code and data

## Related

- [6502-ACE](https://github.com/acwright/6502-ACE) — the hardware, and the index of the whole family
- [6502-BIOS](https://github.com/acwright/6502-BIOS) — the firmware behind the Kernal jump table: `6502.inc` is its 1.6 API, `6502-VDP.inc` its 2.x API
- [6502-PICOVDP](https://github.com/acwright/6502-PICOVDP) — the video card `6502-VDP.inc` is for
- [6502-EMULATOR](https://github.com/acwright/6502-EMULATOR) — run a cartridge without burning an EEPROM (`make run`)
- [6502-PRG](https://github.com/acwright/6502-PRG) — the same idea for RAM programs loaded from BASIC
- [6502-ASM](https://github.com/acwright/6502-ASM) — worked assembly examples
- [6502-DOCS](https://github.com/acwright/6502-DOCS) — the documentation site: the cross-development and assembly guides, and the printable reference cards

## License

MIT License — see [LICENSE](LICENSE).
