import { defineConfig } from "vitest/config"
import base from "../../../vitest.config.js"

// The real configuration — same setup file, same aliases — pointed at the fixtures in this
// directory instead of the suite. harness.test.js runs it in a child process to watch the shared
// afterEach fail these tests; they must never be part of `npm test` itself.
export default defineConfig({
  ...base,
  test: { ...base.test, include: [ "test/javascript/harness_fixtures/*.fixture.js" ] }
})
