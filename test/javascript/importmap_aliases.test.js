import { resolve } from "node:path"
import { describe, expect, test } from "vitest"
import { importmapAliases, importmapAliasesFrom } from "./importmap_aliases.js"

const root = resolve(import.meta.dirname, "../..")

describe("importmapAliases", () => {
  test("aliases every directory config/importmap.rb pins, under the name it pins it", () => {
    expect(importmapAliasesFrom(root)).toEqual({
      controllers: resolve(root, "app/javascript/controllers"),
      helpers: resolve(root, "app/javascript/helpers")
    })
  })

  test("ignores single pins and comments", () => {
    const source = [
      "# pin_all_from is how a whole directory gets pinned",
      'pin "@hotwired/stimulus", to: "stimulus.min.js"',
      'pin_all_from "app/javascript/widgets", under: "widgets", preload: false'
    ].join("\n")

    expect(importmapAliases(source, "/r")).toEqual({ widgets: "/r/app/javascript/widgets" })
  })

  test("refuses a pin_all_from line it cannot read rather than skipping it", () => {
    expect(() => importmapAliases('pin_all_from "app/javascript/widgets"', "/r"))
      .toThrow(/cannot read an alias from `pin_all_from "app\/javascript\/widgets"`/)
  })
})
