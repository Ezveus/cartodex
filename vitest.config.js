import { defineConfig } from "vitest/config"
import { importmapAliasesFrom } from "./test/javascript/importmap_aliases.js"

// Dev/test only: importmap stays the only way the app serves JavaScript. See
// test/javascript/README.md for how to write a controller test.
export default defineConfig({
  resolve: {
    alias: importmapAliasesFrom(import.meta.dirname)
  },
  test: {
    environment: "jsdom",
    include: [ "test/javascript/**/*.test.js" ],
    setupFiles: [ "test/javascript/setup.js" ],
    restoreMocks: true,
    unstubGlobals: true
  }
})
