# VDP assessment: 6502-CRT

> An outline, not a plan. The detailed plan for this repository goes in `VDP-PLAN.md`,
> written in a session of its own. Surveyed 2026-09-16 across the whole workspace.

## The change

The ACE moves from a Pico9918 running stock TMS9918A firmware to the **6502-PICOVDP**
(`6502-PICOVDP/SPEC.md`) on PICO9918 PRO v2.0 hardware, running **BIOS 2.x**. Everything
else stays where it is: COB, DEV, KIM, VCS, PicoCalc, and any ACE whose card cannot be
reflashed (RP2040 pico9918 v1.0–1.3). Those keep the stock firmware and **BIOS 1.x (1.5)**.

- **Legacy** in these documents means TMS9918A + BIOS 1.x. **VDP** means PICOVDP + BIOS 2.x.
- **Compatibility runs one way.** The PICOVDP's legacy submode runs Text and Graphics I
  programs unchanged, so BIOS 1.5 and existing cartridges run on it. Graphics II and
  Multicolor fall back to Graphics I and draw garbage. Register writes above 7 no longer
  alias, so F18A tricks break. Sprites per line are 16 by default, not 4. Nothing written
  for the VDP runs on a TMS9918A.
- **BIOS 2.0 is assumed to be:** BIOS 1.5, plus the NVRAM save slots in
  `6502-BIOS/PLAN.md`, plus the VDP work in `6502-EMULATOR`'s
  `docs/handoff/6502-BIOS.md` (branch `v3-vdp`). Existing jump-table addresses stay put.
  A later BIOS redesign may revise this.

## Decisions already made

- No new repositories.
- **6502-EMULATOR** makes the video card an option (TMS9918A or PICOVDP): one app, one
  site. It also publishes a frozen 2.6.9 web build at a versioned path for the legacy docs.
- **6502-DOCS** is versioned: legacy docs are frozen at `/6502-DOCS/v1/`, and the main
  site is rewritten for the VDP.
- **6502-BIOS** gets a `v1.x` maintenance branch; `main` becomes 2.x.
- **Assembly and C projects** get a VDP include chosen by a build option, not branches.
- **EhBASIC and vc83basic** stay 1.x. **PicoCalc** stays legacy. **The YouTube series**
  teaches the legacy VDP and mentions the new features.

## Order across the workspace

1. **6502-PICOVDP:** firmware proven on the PRO (its Phases 9–11). This gates the
   hardware switch, not the software work.
2. **6502-EMULATOR:** frozen 2.6.9 web build at `/6502-EMULATOR/v2/`.
3. **6502-DOCS:** `v1` branch published at `/6502-DOCS/v1/`, embeds pinned to step 2.
4. **6502-EMULATOR:** `v3-vdp` merged, with the card as an option; tagged 3.x.
5. **6502-BIOS:** `v1.x` cut; 2.0 built on `main`. This can start any time, because the
   `v3-vdp` emulator already runs the PICOVDP.
6. **6502-ASM** sets the VDP include convention. 6502-CRT, 6502-PRG, 6502-BIN and 6502-C
   follow it.
7. The emulator bundles BIOS 2.0. 6502-DOCS `main` is rewritten. 6502-ACE, bastok,
   WIZARDSLAB, 6502-EHBASIC, vc83basic and 6502-ASSEMBLY follow.

---

## This repository's role

The cartridge template: `Cart.asm` → `Cart.crt`, a 16 KB ROM at `$C000` that overrides
BASIC and the Monitor while the Kernal at `$A000` stays mapped. A VDP cartridge is still a
cartridge. What changes is which Kernal and which card it may assume.

## Where it stands

- `Makefile` targets: `build`, `view`, `run` (`6502 run --cart Cart.crt`), `eeprom`.
- Its `6502.inc` is the settled legacy include, byte-identical across the workspace and
  checked against the BIOS v1.5 build (see 6502-ASM's assessment).
- `README.md` tables Kernal entries (for example `$A07B KernalVersion`) and links
  6502-BIOS as the API source.

## Work outline

**Blocked on 6502-ASM's convention.**

1. Adopt the VDP include and build option exactly as 6502-ASM defines them.
2. `run` for a VDP build selects the emulator's PICOVDP card (flag named by 6502-EMULATOR).
3. `README.md`:
   - Which include to start from.
   - A VDP cartridge needs BIOS 2.x and a converted ACE, and can check `KernalVersion`
     (major ≥ 2) and the card-type byte at startup.
   - The jump table grows with NVRAM slot and VDP entries.
4. Optionally, a startup guard in `Cart.asm` for VDP builds that prints a message on a
   legacy machine. It makes a good template idiom; the plan decides.

## Linked repositories

| Repository | Path | Why |
|---|---|---|
| 6502-ASM | `~/Developer/Assembly/6502-ASM` | Defines the include and build-option convention |
| 6502-BIOS | `~/Developer/Assembly/6502-BIOS` | BIOS 2.0 jump table, card detection byte |
| 6502-EMULATOR | `~/Developer/NodeJS/6502-EMULATOR` | Card flag for `make run` |
| 6502-PRG, 6502-BIN | `~/Developer/Assembly/6502-PRG`, `~/Developer/Assembly/6502-BIN` | Sibling templates with the same include; keep them in step |
