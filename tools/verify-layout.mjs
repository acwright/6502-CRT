#!/usr/bin/env node
// `make verify-layout` — prove that ld65 still writes the banks in the order
// the config declares them.
//
// The banked configs rest on one undocumented-ish guarantee: **ld65 writes each
// MEMORY area that names a file to that file in the order the areas are
// declared**, and that order *is* the flash's linear layout. Nothing else in the
// build depends on it and nothing else would notice if it changed — a future
// ld65 that reordered areas would produce a perfectly valid-looking image with
// every bank in the wrong place, and the first sign of it would be a cart that
// runs in an emulator whose mapper agrees with the same mistake, or does not
// run on hardware at all.
//
// So: assemble a cartridge with a distinct marker in every bank, build it with
// each config, and check that each marker is at the offset the declaration
// order says it should be.
//
//   node tools/verify-layout.mjs [config.cfg ...]
//
// With no arguments it checks all four banked configs.

import { execFileSync } from 'node:child_process'
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'

const DEFAULT_CONFIGS = ['6502-128K.cfg', '6502-256K.cfg', '6502-512K.cfg', '6502-1M.cfg']

/**
 * The file-backed MEMORY areas, in declaration order — which is the thing under
 * test, so it is read from the config and never assumed.
 */
function memoryAreas(cfg, path) {
  const block = /MEMORY\s*\{([\s\S]*?)\n\}/.exec(cfg)
  if (!block) throw new Error(`no MEMORY block in ${path}`)

  const areas = []
  for (const line of block[1].split('\n')) {
    const m = /^\s*([A-Za-z0-9_]+)\s*:(.*)$/.exec(line)
    if (!m) continue
    const [, name, rest] = m
    if (!/file\s*=/.test(rest)) continue
    const size = /size\s*=\s*\$([0-9A-Fa-f]+)/.exec(rest)
    if (!size) continue
    areas.push({ name, size: parseInt(size[1], 16) })
  }
  return areas
}

/** Four bytes that will not occur by accident in a $FF-filled image. */
function marker(index) {
  return Buffer.from([0x4c, 0x59, index & 0xff, (index >> 8) & 0xff])
}

function sourceFor(areas) {
  const lines = ['.setcpu "65C02"', '']

  areas.forEach((area, i) => {
    if (area.name === 'VECTORS') return
    const m = marker(i)
    lines.push(`.segment "${area.name}"`)
    if (area.name === 'FIXED') lines.push('LayoutStart:')
    lines.push(`  .byte $${m[0].toString(16)}, $${m[1].toString(16)}, ` +
               `$${m[2].toString(16).padStart(2, '0')}, $${m[3].toString(16).padStart(2, '0')}`)
    lines.push('')
  })

  // A cartridge has to supply its own vectors, and FIXED has to hold something
  // for them to point at.
  lines.push('.segment "VECTORS"')
  lines.push('  .word LayoutStart')
  lines.push('  .word LayoutStart')
  lines.push('  .word LayoutStart')
  lines.push('')

  return lines.join('\n')
}

const configs = process.argv.slice(2)
const targets = configs.length > 0 ? configs : DEFAULT_CONFIGS

let failures = 0

for (const configPath of targets) {
  const cfg = readFileSync(configPath, 'utf8')
  const areas = memoryAreas(cfg, configPath)

  const dir = mkdtempSync(join(tmpdir(), 'crt-layout-'))
  const asm = join(dir, 'layout.asm')
  const out = join(dir, 'layout.crt')

  try {
    writeFileSync(asm, sourceFor(areas))
    execFileSync('cl65', ['-t', 'none', '-C', configPath, '-o', out, asm], { stdio: 'pipe' })

    const image = readFileSync(out)
    const expected = areas.reduce((t, a) => t + a.size, 0)

    const problems = []
    if (image.length !== expected) {
      problems.push(`image is ${image.length} bytes, the config declares ${expected}`)
    }

    let at = 0
    areas.forEach((area, i) => {
      if (area.name !== 'VECTORS') {
        const want = marker(i)
        const got = image.subarray(at, at + want.length)
        if (!got.equals(want)) {
          problems.push(
            `${area.name} is not at offset $${at.toString(16).padStart(5, '0')} ` +
              `(found ${got.toString('hex')}, wanted ${want.toString('hex')})`
          )
        }
      }
      at += area.size
    })

    if (problems.length > 0) {
      failures++
      console.error(`FAIL  ${configPath}`)
      for (const p of problems) console.error(`      ${p}`)
    } else {
      console.log(`ok    ${configPath} — ${areas.length} areas in declaration order, ` +
                  `${image.length.toLocaleString('en-US')} bytes`)
    }
  } finally {
    rmSync(dir, { recursive: true, force: true })
  }
}

if (failures > 0) {
  console.error('')
  console.error('ld65 is no longer writing memory areas in declaration order, or the')
  console.error('configs have been reordered. Every banked image is scrambled until this')
  console.error('is resolved — see the note at the top of any 6502-<target>.cfg.')
  process.exit(1)
}
