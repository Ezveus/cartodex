import { readdirSync } from "node:fs"
import { matchesGlob, relative, resolve } from "node:path"
import { describe, expect, test } from "vitest"
import config from "../../vitest.config.js"
import { importmapAliasesFrom } from "./importmap_aliases.js"

const root = resolve(import.meta.dirname, "../..")

describe("vitest.config.js", () => {
  test("takes its aliases from config/importmap.rb rather than restating them", () => {
    expect(config.resolve.alias).toEqual(importmapAliasesFrom(root))
  })

  // A narrower glob drops whole directories and still exits 0, with no warning.
  test("collects every *.test.js under test/javascript, and none of the harness fixtures", () => {
    const files = readdirSync(resolve(root, "test/javascript"), { recursive: true }).map((file) =>
      relative(root, resolve(root, "test/javascript", file)))
    const collected = (file) => config.test.include.some((pattern) => matchesGlob(file, pattern))

    const tests = files.filter((file) => file.endsWith(".test.js"))
    expect(tests.length).toBeGreaterThan(5)
    expect(tests.filter((file) => !collected(file))).toEqual([])
    expect(files.filter((file) => file.includes("harness_fixtures/") && collected(file))).toEqual([])
  })
})
