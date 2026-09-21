6502-CRT
========

A 6502 assembly language cartridge template for the [AC6502](https://github.com/acwright/6502-ACE) family of computer systems.

> 📖 **Guide:** [AC6502 Documentation](https://acwright.github.io/6502-DOCS/) — the user's and programmer's guide for the whole family.
> This template is walked through end to end in [Writing a cartridge](https://acwright.github.io/6502-DOCS/assembly/cartridges).

## Overview

Cartridges for this system overlay the ROM address space from `$C000–$FFFF`, replacing the BASIC interpreter, Wozmon, the CPU vectors and, on BIOS 1.x, the Monitor with custom code. The Kernal remains accessible underneath — `$A000–$B7FF` plus the character set at `$B800–$BFFF` on BIOS 1.x, all of `$A000–$BFFF` on BIOS 2.x — providing hardware initialization, character I/O, video, sound, storage, and other system services through a stable jump table.

The template builds two ways from the same source: `make` for any ACE on BIOS 1.x with a TMS9918A, and `make VDP=1` for an ACE converted to a [6502-PICOVDP](https://github.com/acwright/6502-PICOVDP) on BIOS 2.x. See [Building for the 6502-PICOVDP](#building-for-the-6502-picovdp).

When the cartridge works, [6502-ASM](https://github.com/acwright/6502-ASM) is
where a small one goes: demos, samples, scratchpads and tests, each in a
directory of its own, and `HelloWorldCart` and `BankedDemo` there are
cartridges of this shape. [6502-BAS](https://github.com/acwright/6502-BAS) and
[6502-C](https://github.com/acwright/6502-C) are the same collection for BASIC
and C. A finished game or application gets a repository of its own instead.

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

This is the flat 32 KB cartridge. A **Flash Cart** splits `$C000–$FFFF` into a switchable 8 KB window and a fixed 8 KB the vectors live in, for 120 KB to 1 MB of code — see [Building for the Flash Cart](#building-for-the-flash-cart).

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

## Building for the Flash Cart

`make FLASH=512K` builds `Cart-512K.crt`: a **banked** cartridge for the AC6502 Flash Cart, a byte-exact image of one or two SST39SF0x0 flash chips instead of a 32 KB EEPROM. Everything it adds to `Cart.asm` is inside `.ifdef FLASH`, so `make` with no arguments still produces the same 32,768 bytes it always has.

**The ROM Cart is not replaced.** This is a second axis, like `VDP=1`, and the two compose.

### The five sizes, and how they are named

```
Cart[-VDP][-<target>].crt
```

| Target | Bytes | Part | Mapper | Usable banks | Fixed bank | Code space |
|---|---|---|---|---|---|---|
| *(none)* | 32,768 | 28C256 / 27C256 | flat | — | — | 16,378 bytes |
| `-128K` | 131,072 | SST39SF010A | banked | `$00`–`$0E` | `$0F` | 120 KB banked + 8 KB fixed |
| `-256K` | 262,144 | SST39SF020A | banked | `$00`–`$1E` | `$1F` | 240 KB banked + 8 KB fixed |
| `-512K` | 524,288 | SST39SF040 | banked | `$00`–`$3E` | `$3F` | 504 KB banked + 8 KB fixed |
| `-1M` | 1,048,576 | SST39SF040 ×2 | banked | `$00`–`$3E`, `$40`–`$7F` | `$3F` | 1,016 KB banked + 8 KB fixed |

**`-VDP` comes first, then the target** — `Cart-VDP-512K.crt`, never `Cart-512K-VDP.crt`. The build variant, then the hardware target. The Makefile is the one place that ordering can be enforced, and it enforces it.

A `.crt` is a byte-exact image of the chip and nothing else: no header, no footer, no metadata. **The mapper is decided by the file's size, never by its name** — a loader that sees 262,144 bytes loads a 256K cart whatever the file is called. The name is for whoever is reading `ls`.

### The memory map

| Range | Contents |
|---|---|
| `$C000–$DFFF` | **switchable window** — 8 KB of whichever bank the register last selected |
| `$E000–$FFF9` | **fixed region** — always the primary chip's last 8 KB, whatever the register holds |
| `$FFFA–$FFFF` | **CPU vectors**, inside the fixed region |

The fixed region is the whole point of the arrangement: **the vectors can never be banked out from under the CPU**, so a reset or an interrupt always lands on real code no matter which bank was selected when it happened.

The linker config gives each bank a segment, and **the segment's name is the value you write**:

```asm
.segment "BANK07"               ; reached with lda #$07 / jsr SetBank
Level1Data:  .byte ...
```

`$E000` is the bank register. It is **write-only** — eight bits, at *any* address in `$E000–$FFFF` — and a write there latches it and reaches no flash, so writing the register is never also a flash write. `RESB` clears it to 0. Bits above the part's bank count alias down, bit 6 selects the second chip on a `-1M` cart, and bit 7 goes nowhere.

### `SetBank` and the shadow

```asm
.segment "FIXED"

SetBank:                        ; A = bank value; preserves X and Y
  sta BANKSHDW                  ; shadow first
  sta BANK                      ; then the register
  rts
```

The register **cannot be read back**, so a cart that loses track of which bank it selected has no way to recover it. `BANKSHDW` (`$3A`, the first byte `6502.inc` marks free for a program that has taken the machine over) is the only record there is, and the template claims that byte and says so.

The shadow is written **first**, deliberately. If an interrupt lands between the two stores, the handler sees a shadow one instruction *ahead* of the hardware rather than one behind, and restoring the hardware from the shadow on the way out puts the two back in agreement. The other order leaves them permanently disagreed.

### The two bugs

1. **Switching banks from inside a bank.** `jsr SetBank` from code at `$C000–$DFFF` returns to an address that no longer holds the calling code. The machine does not fault; it runs whatever the new bank has there. **Always bank-switch from `FIXED`.**
2. **An interrupt during a bank-relative sequence.** The default Kernal IRQ handler lives at `$A000–$BFFF` and is unaffected. A cartridge's *own* handler that touches banked data must live in `FIXED`, and must save the current bank from `BANKSHDW`, select its own, and restore through `SetBank` before it returns.

Everything that must live in `FIXED`: the reset, IRQ and NMI entry points and their trampolines; `SetBank` itself; any routine that calls into a bank and expects to come back; and the *caller* of a flash-writing routine — the routine itself runs from RAM.

`Cart.asm` ships a worked cross-bank call — a message in `BANK01` printed by a routine in `FIXED` — because the shape of it is the whole skill.

### Build commands

| Command | Output |
|---|---|
| `make` | `Cart.crt`, 32 KB, unchanged |
| `make VDP=1` | `Cart-VDP.crt`, unchanged |
| `make FLASH=512K` | `Cart-512K.crt` |
| `make VDP=1 FLASH=1M` | `Cart-VDP-1M.crt` |
| `make all-flash` | every `FLASH` target for the current `VDP` setting |
| `make size FLASH=512K` | how full each bank is, and how much of the fixed region is left |
| `make run FLASH=512K` | runs it in the emulator |
| `make flash FLASH=512K` | burns it through the Flash Helper with `6502-flash program` |
| `make configs` / `check-configs` | regenerate the four banked linker configs; `--check` fails on a stale one |
| `make clean` | removes every variant, all ten names |

**`make eeprom` refuses when `FLASH` is set**, and says where to go instead. A 512 KB image silently truncated into a 28C256 is a confusing afternoon.

`make size` is the one to know about. A banked cart runs out of **fixed region** long before it runs out of banks — every bank switch, every interrupt entry and every routine that calls into a bank has to live in those 8,186 bytes — and nothing else tells you how much of it is left:

```
Cart-512K.crt  524,288 bytes

  BANK01        23 /   8,192    0%  #...................
  FIXED         81 /   8,186    1%  #...................
  VECTORS        6 /       6  100%  ####################

  1 of 63 banks in use, 62 empty  (516,073 bytes free in the window)
  FIXED: 8,105 bytes free of 8,186
```

It works on the flat cart too, where it reports `CART` out of 16,378.

The four `.cfg` files are generated by `tools/make-cart-cfg.mjs` and committed — 15 to 127 near-identical stanzas is how a hand-written set drifts — so they can be read, diffed and copied.

### Saves

A Flash Cart can write to itself, which is how a cartridge saves: erase a 4 KB sector, then program bytes into it. `Cart.asm` carries a **commented** `SaveGame` / `LoadGame` pair showing the command sequences, why the routine has to run from RAM with interrupts off, and both of the standard polling loops. By convention across the family, saves live in the **top 4 KB sector of the highest usable bank**, which is the same unit the `.sav` sidecar and `6502-flash merge` work in.

A save written while testing **can never end up on a chip by accident**: emulators keep it in a `<stem>.sav` file beside the `.crt`, the `.crt` itself is opened read-only, and `6502-flash program` has no flag that folds one in. For the whole story, with a runnable sample, see the 6502-DOCS chapter *Bigger cartridges*.

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
| `make FLASH=512K` | Build a banked Flash Cart image (`Cart-512K.crt`) — see [Building for the Flash Cart](#building-for-the-flash-cart) |
| `make view` | Display hexdump of the built ROM |
| `make size` | Report how much of the cartridge each segment uses |
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

`make VDP=1` writes `Cart-VDP.crt` and `Cart-VDP.lst` beside them, and `make VDP=1 eeprom` burns `Cart-VDP.crt`. Adding `FLASH=` to either produces a banked image instead — `Cart-512K.crt`, `Cart-VDP-1M.crt` — which is burnt with `make flash`, not `make eeprom`.

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
- [6502-BIN](https://github.com/acwright/6502-BIN) — the same idea for a raw binary with no BASIC stub
- [6502-ASM](https://github.com/acwright/6502-ASM) — where small assembly programs live: demos, samples and tests, with worked examples of this template
- [6502-BAS](https://github.com/acwright/6502-BAS) / [6502-C](https://github.com/acwright/6502-C) — the same collection for BASIC listings and for C
- [6502-DOCS](https://github.com/acwright/6502-DOCS) — the documentation site: the cross-development and assembly guides, and the printable reference cards

## License

MIT License — see [LICENSE](LICENSE).
