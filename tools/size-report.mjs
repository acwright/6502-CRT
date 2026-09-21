#!/usr/bin/env node
// `make size` — how full each bank is.
//
// A banked cartridge author asks this constantly and has nowhere good to look:
// ld65's map file lists the segments that ended up with something in them, and
// says nothing about the ones that did not or about how much room is left in
// the ones that did. The sizes are in the linker config and the usage is in the
// map, so this reads both.
//
//   node tools/size-report.mjs <config.cfg> <out.map> <out.crt>
//
// Works for the flat 32K cart as well as the four banked targets — it takes the
// shape of the cartridge from the config rather than being told.

import { readFileSync, statSync } from 'node:fs'

const [, , configPath, mapPath, imagePath] = process.argv

if (!configPath || !mapPath) {
  console.error('usage: size-report.mjs <config.cfg> <out.map> [out.crt]')
  process.exit(2)
}

/**
 * The MEMORY block, in declaration order — which for these configs is the
 * flash's linear layout, so the report reads in the same order the chip does.
 *
 * Only areas that name a file are counted: anything else is not in the image.
 */
function memoryAreas(cfg) {
  const block = /MEMORY\s*\{([\s\S]*?)\n\}/.exec(cfg)
  if (!block) throw new Error(`no MEMORY block in ${configPath}`)

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

/** Segment name → bytes used. Segments with nothing in them are absent. */
function segmentSizes(map) {
  const block = /Segment list:\n-+\n[\s\S]*?\n-+\n([\s\S]*?)\n\n/.exec(map)
  if (!block) throw new Error(`no segment list in ${mapPath}`)

  const used = new Map()
  for (const line of block[1].split('\n')) {
    const m = /^(\S+)\s+[0-9A-Fa-f]+\s+[0-9A-Fa-f]+\s+([0-9A-Fa-f]+)/.exec(line)
    if (m) used.set(m[1], parseInt(m[2], 16))
  }
  return used
}

const n = (v) => v.toLocaleString('en-US')

function bar(used, size, width = 20) {
  if (size === 0) return ''
  const filled = Math.min(width, Math.ceil((used / size) * width))
  return '#'.repeat(filled) + '.'.repeat(width - filled)
}

const areas = memoryAreas(readFileSync(configPath, 'utf8'))
const used = segmentSizes(readFileSync(mapPath, 'utf8'))

// PAD is the 16 KB of $00 below a flat cart that the machine never reads as
// cartridge ROM. It is in the file and it is not space anyone can use.
const rows = areas.filter((a) => a.name !== 'PAD')

const banks = rows.filter((a) => /^BANK/.test(a.name))
const occupied = rows.filter((a) => (used.get(a.name) ?? 0) > 0)

const header = imagePath
  ? `${imagePath}  ${n(statSync(imagePath).size)} bytes`
  : configPath
console.log('')
console.log(header)
console.log('')

const width = Math.max(...rows.map((a) => a.name.length), 7)
for (const area of occupied) {
  const u = used.get(area.name) ?? 0
  const pct = area.size ? Math.round((u / area.size) * 100) : 0
  console.log(
    `  ${area.name.padEnd(width)}  ${n(u).padStart(7)} / ${n(area.size).padStart(7)}` +
      `  ${String(pct).padStart(3)}%  ${bar(u, area.size)}`
  )
}

if (occupied.length === 0) console.log('  (nothing in the image)')

console.log('')

if (banks.length > 0) {
  const inUse = banks.filter((a) => (used.get(a.name) ?? 0) > 0).length
  const free = banks.reduce((t, a) => t + a.size - (used.get(a.name) ?? 0), 0)
  console.log(
    `  ${inUse} of ${banks.length} banks in use, ${banks.length - inUse} empty` +
      `  (${n(free)} bytes free in the window)`
  )
}

// The fixed region is the one that runs out first and the one that hurts: every
// bank switch, every interrupt entry and every routine that calls into a bank
// has to live there.
for (const name of ['FIXED', 'CART']) {
  const area = rows.find((a) => a.name === name)
  if (!area) continue
  const u = used.get(name) ?? 0
  console.log(`  ${name}: ${n(area.size - u)} bytes free of ${n(area.size)}`)
}

console.log('')
