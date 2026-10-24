import { readFileSync } from "node:fs"
import { resolve } from "node:path"

// The module names a controller imports are the ones config/importmap.rb pins, so the aliases
// that make those imports resolve under Vitest are read from that file rather than restated: a
// directory pinned tomorrow is importable under test the same day, and the two lists cannot
// drift. Only `pin_all_from` needs an alias — a single `pin` names either an npm package
// (`@hotwired/stimulus`, resolved from node_modules) or a file no controller imports.
//
// A `pin_all_from` line this cannot read throws instead of being skipped. Skipped, its modules
// would fail to resolve under test with an error that reads like a typo in the test.
const PIN_ALL_FROM = /^\s*pin_all_from\s+"([^"]+)"\s*,\s*under:\s*"([^"]+)"/

export function importmapAliases(source, root) {
  const aliases = {}

  for (const line of source.split("\n")) {
    if (!/^\s*pin_all_from\b/.test(line)) continue

    const match = line.match(PIN_ALL_FROM)
    if (!match) throw new Error(`config/importmap.rb: cannot read an alias from \`${line.trim()}\``)

    const [, directory, name] = match
    aliases[name] = resolve(root, directory)
  }

  return aliases
}

export function importmapAliasesFrom(root) {
  return importmapAliases(readFileSync(resolve(root, "config/importmap.rb"), "utf8"), root)
}
