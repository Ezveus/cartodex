import { spawnSync } from "node:child_process"
import { mkdtempSync, readFileSync, rmSync } from "node:fs"
import { tmpdir } from "node:os"
import { join, resolve } from "node:path"
import { afterAll, beforeAll, describe, expect, test } from "vitest"

// support.test.js calls resetSupport() by hand; this proves the shared afterEach really calls it.
// It runs Vitest in a child process over harness_fixtures/ — the real setup file and aliases — and
// reads which tests failed, and why.
const root = resolve(import.meta.dirname, "../..")
let results

beforeAll(() => {
  const output = mkdtempSync(join(tmpdir(), "harness-"))
  const report = join(output, "report.json")
  const env = Object.fromEntries(Object.entries(process.env).filter(([ name ]) => !name.startsWith("VITEST")))

  try {
    const run = spawnSync(process.execPath, [
      resolve(root, "node_modules/vitest/vitest.mjs"), "run",
      "--config", "test/javascript/harness_fixtures/vitest.config.js",
      "--reporter=json", `--outputFile=${report}`
    ], { cwd: root, env, encoding: "utf8", timeout: 60_000 })

    expect(run.status, run.stderr).toBe(1)
    const [ file ] = JSON.parse(readFileSync(report, "utf8")).testResults
    results = Object.fromEntries(file.assertionResults.map((result) =>
      [ result.title, { status: result.status, failure: result.failureMessages.join("\n") } ]))
  } finally {
    rmSync(output, { recursive: true, force: true })
  }
}, 60_000)

afterAll(() => { results = undefined })

describe("the shared afterEach", () => {
  test("lets a clean test pass, so the failures below are the harness's doing", () => {
    expect(results["control: a clean test"]).toEqual({ status: "passed", failure: "" })
  })

  test.each([
    [ "a controller throws in connect", /fixture: boom in connect/ ],
    [ "a controller throws in an action", /fixture: boom in action/ ],
    [ "a request is made without ever calling stubFetch", /no reply queued: GET \/api\/unstubbed/ ],
    [ "a request outruns the queued replies", /no reply queued: POST \/api\/second/ ],
    [ "a queued reply is never requested", /1 queued fetch reply was never requested/ ]
  ])("fails a test in which %s", (title, reason) => {
    expect(results[title].status).toBe("failed")
    expect(results[title].failure).toMatch(reason)
  })
})
