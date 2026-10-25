import { describe, expect, test, vi } from "vitest"
import DeckRowsController from "controllers/deck_rows_controller"
import CardSearchController from "controllers/card_search_controller"
import DisclosureController from "controllers/disclosure_controller"
import { captureEvents, flashMessages, jsonResponse, mount, requests, settle, stubFetch } from "../support"

// Hand-written markup following the DOM contract of
// docs/superpowers/plans/2026-10-24-deck-fingerprint-rows.md ("DOM (lane B renders, lane C
// reads)"). The controller is meant to know nothing else, so nothing else is rendered here.

const controllers = { "deck-rows": DeckRowsController }

function writeButton(focusKey, { url = "/api/decks/k/cards/1", method = "PATCH", body = { deck_card: { quantity: 2 } }, disabled = false } = {}) {
  return `<button data-action="deck-rows#write"
    data-deck-rows-url-param="${url}"
    data-deck-rows-method-param="${method}"
    data-deck-rows-body-param='${JSON.stringify(body)}'
    data-deck-rows-failure-param="Couldn't update the card"
    data-focus-key="${focusKey}"${disabled ? " disabled" : ""}>+</button>`
}

// A fingerprint row (type view), or with `printing: true` a set-view printing row. `label` makes
// two renders of the same key distinguishable; `disclosure` adds an expand toggle.
function row(key, { fingerprint = key, label = key, printing = false, disclosure = false, focus = `qty-plus-${key}`, disabled = false } = {}) {
  const id = `deck-printings-${key.replace(/:/g, "-")}`
  const toggle = disclosure
    ? `<button class="deck-printings-toggle" aria-expanded="false" aria-controls="${id}" data-action="disclosure#toggle">▸</button>
       <ul class="deck-printing-list" id="${id}" hidden><li class="deck-printing-row">sub</li></ul>`
    : ""
  return `<li class="${printing ? "deck-printing-row" : "deck-fingerprint"}" data-row-key="${key}" data-fingerprint-key="${fingerprint}">
    <div class="deck-card-line"><span class="label">${label}</span>${writeButton(focus, { disabled })}</div>${toggle}
  </li>`
}

function typeSection(key, rows, { total = 0, unique = 0, heading = "h2", classes = "deck-section" } = {}) {
  return `<div class="${classes}" data-section-key="${key}">
    <${heading}>${key} (<span data-section-total>${total}</span> — <span data-section-unique>${unique}</span> unique)</${heading}>
    <ul class="deck-card-list">${rows.join("")}</ul>
  </div>`
}

function subsection(key, rows, counts = {}) {
  return typeSection(key, rows, { ...counts, heading: "h3", classes: "deck-section deck-subsection" })
}

function group(key, children) {
  return `<div class="deck-section-group" data-section-key="${key}"><h2>Trainer</h2>${children.join("")}</div>`
}

function setSection(key, rows, { total = 0, noun = "cards" } = {}) {
  return `<div class="deck-section deck-set-section" data-section-key="${key}" data-set-code="${key}">
    <h2>${key} · <span data-section-total>${total}</span> <span data-section-noun>${noun}</span></h2>
    <ul class="deck-card-list">${rows.join("")}</ul>
  </div>`
}

const addButton = `<button class="card-search-add-btn" data-action="card-search#add" data-card-id="99">+</button>`
const searchFragment = `<div data-controller="card-search" data-card-search-url-value="/api/decks/k/cards?group=type">
  <input data-card-search-target="input" value="new"><div data-card-search-target="results">${addButton}</div></div>`

function page(sections, { total = 10, extraControllers = "", extraActions = "", inner = "" } = {}) {
  return `<div class="deck-show-container" data-controller="deck-rows${extraControllers}"
      data-action="card-search:add->deck-rows#add${extraActions}">
    <span class="stat" data-deck-rows-target="total">${total}</span>
    ${inner}
    <div class="deck-sections" data-deck-rows-target="sections">${sections.join("")}</div>
  </div>`
}

// The answer of every write. Sections not named in `full` carry counts only, the way the server
// sends sections holding no row of this answer.
function answer({ fingerprintKey, rows = [], sections, deck = { has_proxies: false, total: 10 } }) {
  return {
    fingerprint_key: fingerprintKey,
    fingerprint: rows.length ? { key: fingerprintKey } : null,
    rows,
    sections,
    deck
  }
}

function sectionKeys(root) {
  return Array.from(root.querySelectorAll("[data-section-key]"), (element) => element.dataset.sectionKey)
}

function rowKeys(list) {
  return Array.from(list.querySelectorAll(":scope > [data-row-key]"), (element) => element.dataset.rowKey)
}

function listOf(root, sectionKey) {
  return root.querySelector(`[data-section-key="${sectionKey}"] > ul.deck-card-list`)
}

async function apply(rendered, data) {
  await rendered.controller("deck-rows").apply(data)
}

describe("deck_rows_controller", () => {
  test("sends the request its button carries and replaces the row in place", async () => {
    const reply = answer({
      fingerprintKey: "fp-b",
      rows: [ { key: "fp-b", section: "pokemon", html: row("fp-b", { label: "fp-b after" }) } ],
      sections: [ { key: "pokemon", parent: null, total: 4, unique: 3, rows: [ "fp-a", "fp-b", "fp-c" ], html: typeSection("pokemon", []) } ],
      deck: { has_proxies: false, total: 11 }
    })
    stubFetch(jsonResponse(reply))
    const { element } = await mount(page([ typeSection("pokemon", [ row("fp-a"), row("fp-b"), row("fp-c") ], { total: 3, unique: 3 }) ]), controllers)
    const neighbour = element.querySelector('[data-row-key="fp-a"]')

    element.querySelector('[data-row-key="fp-b"] button').click()
    await settle()

    expect(requests()).toMatchObject([ { url: "/api/decks/k/cards/1", method: "PATCH", body: { deck_card: { quantity: 2 } } } ])
    expect(rowKeys(listOf(element, "pokemon"))).toEqual([ "fp-a", "fp-b", "fp-c" ])
    expect(element.querySelector('[data-row-key="fp-b"] .label').textContent).toBe("fp-b after")
    expect(element.querySelector('[data-row-key="fp-a"]')).toBe(neighbour)
    expect(flashMessages()).toEqual([])
  })

  test("inserts a new row before the first following key that is present, else at the end", async () => {
    const rendered = await mount(page([ typeSection("pokemon", [ row("fp-a"), row("fp-d") ]) ]), controllers)
    const sectionRows = [ "fp-a", "fp-b", "fp-c", "fp-d", "fp-e" ]
    const section = { key: "pokemon", parent: null, total: 5, unique: 5, rows: sectionRows, html: typeSection("pokemon", []) }

    // fp-c is absent, so fp-b goes before fp-d.
    await apply(rendered, answer({ fingerprintKey: "fp-b", rows: [ { key: "fp-b", section: "pokemon", html: row("fp-b") } ], sections: [ section ] }))
    expect(rowKeys(listOf(rendered.element, "pokemon"))).toEqual([ "fp-a", "fp-b", "fp-d" ])

    await apply(rendered, answer({ fingerprintKey: "fp-e", rows: [ { key: "fp-e", section: "pokemon", html: row("fp-e") } ], sections: [ section ] }))
    expect(rowKeys(listOf(rendered.element, "pokemon"))).toEqual([ "fp-a", "fp-b", "fp-d", "fp-e" ])
  })

  test("creates a missing section from its html, before the next listed section present", async () => {
    const rendered = await mount(page([
      typeSection("pokemon", [ row("fp-a") ]),
      group("trainer", [ subsection("trainer-item", [ row("fp-i") ]) ]),
      typeSection("energy", [ row("fp-e") ])
    ]), controllers)

    await apply(rendered, answer({
      fingerprintKey: "fp-s",
      rows: [ { key: "fp-s", section: "trainer-supporter", html: row("fp-s") } ],
      sections: [
        { key: "pokemon", parent: null, total: 1, unique: 1 },
        { key: "trainer", parent: null, total: null, unique: null, rows: [], html: group("trainer", []) },
        { key: "trainer-supporter", parent: "trainer", total: 1, unique: 1, rows: [ "fp-s" ], html: subsection("trainer-supporter", []) },
        { key: "trainer-item", parent: "trainer", total: 1, unique: 1 },
        { key: "energy", parent: null, total: 1, unique: 1 }
      ]
    }))

    expect(sectionKeys(rendered.element)).toEqual([ "pokemon", "trainer", "trainer-supporter", "trainer-item", "energy" ])
    const supporter = rendered.element.querySelector('[data-section-key="trainer-supporter"]')
    expect(supporter.parentElement.dataset.sectionKey).toBe("trainer")
    expect(rowKeys(listOf(rendered.element, "trainer-supporter"))).toEqual([ "fp-s" ])
  })

  test("creates a missing Trainer group with its child, between the sections around it", async () => {
    const rendered = await mount(page([ typeSection("pokemon", [ row("fp-a") ]), typeSection("energy", [ row("fp-e") ]) ]), controllers)

    await apply(rendered, answer({
      fingerprintKey: "fp-t",
      rows: [ { key: "fp-t", section: "trainer-tool", html: row("fp-t") } ],
      sections: [
        { key: "pokemon", parent: null, total: 1, unique: 1 },
        { key: "trainer", parent: null, total: null, unique: null, rows: [], html: group("trainer", []) },
        { key: "trainer-tool", parent: "trainer", total: 1, unique: 1, rows: [ "fp-t" ], html: subsection("trainer-tool", []) },
        { key: "energy", parent: null, total: 1, unique: 1 }
      ]
    }))

    expect(sectionKeys(rendered.element)).toEqual([ "pokemon", "trainer", "trainer-tool", "energy" ])
    expect(rendered.element.querySelector('[data-section-key="trainer-tool"]').parentElement.dataset.sectionKey).toBe("trainer")
    expect(rendered.element.querySelector('[data-deck-rows-target="sections"]').lastElementChild.dataset.sectionKey).toBe("energy")
  })

  test("appends a new section when no listed section follows it", async () => {
    const rendered = await mount(page([ typeSection("pokemon", [ row("fp-a") ]) ]), controllers)

    await apply(rendered, answer({
      fingerprintKey: "fp-e",
      rows: [ { key: "fp-e", section: "energy", html: row("fp-e") } ],
      sections: [
        { key: "pokemon", parent: null, total: 1, unique: 1 },
        { key: "energy", parent: null, total: 1, unique: 1, rows: [ "fp-e" ], html: typeSection("energy", []) }
      ]
    }))

    expect(sectionKeys(rendered.element)).toEqual([ "pokemon", "energy" ])
  })

  test("in the set view, removes the fingerprint's rows the answer no longer lists and keeps the others", async () => {
    const rendered = await mount(page([
      setSection("set-2", [ row("printing:21", { fingerprint: "fp-budew", printing: true }), row("printing:22", { fingerprint: "fp-other", printing: true }) ]),
      setSection("set-1", [ row("printing:11", { fingerprint: "fp-budew", printing: true }) ])
    ]), controllers)
    const other = rendered.element.querySelector('[data-row-key="printing:22"]')

    await apply(rendered, answer({
      fingerprintKey: "fp-budew",
      rows: [ { key: "printing:11", section: "set-1", html: row("printing:11", { fingerprint: "fp-budew", printing: true, label: "3x" }) } ],
      sections: [
        { key: "set-2", parent: null, total: 1, noun: "card" },
        { key: "set-1", parent: null, total: 3, noun: "cards", rows: [ "printing:11" ], html: setSection("set-1", []) }
      ]
    }))

    expect(rowKeys(listOf(rendered.element, "set-2"))).toEqual([ "printing:22" ])
    expect(rendered.element.querySelector('[data-row-key="printing:22"]')).toBe(other)
    expect(rendered.element.querySelector('[data-row-key="printing:11"] .label').textContent).toBe("3x")
  })

  test("removes the sections the answer no longer lists, and the row of a fingerprint that left the deck", async () => {
    const rendered = await mount(page([
      typeSection("pokemon", [ row("fp-a") ]),
      group("trainer", [ subsection("trainer-stadium", [ row("fp-st") ]) ])
    ]), controllers)

    await apply(rendered, answer({
      fingerprintKey: "fp-st",
      rows: [],
      sections: [ { key: "pokemon", parent: null, total: 1, unique: 1 } ]
    }))

    expect(sectionKeys(rendered.element)).toEqual([ "pokemon" ])
    expect(rendered.element.querySelector('[data-row-key="fp-st"]')).toBeNull()
  })

  test("writes every section's counts into its own heading, never into a child's", async () => {
    const rendered = await mount(page([
      typeSection("pokemon", [ row("fp-a") ], { total: 1, unique: 1 }),
      group("trainer", [ subsection("trainer-item", [ row("fp-i") ], { total: 4, unique: 1 }) ])
    ]), controllers)

    await apply(rendered, answer({
      fingerprintKey: "fp-a",
      rows: [ { key: "fp-a", section: "pokemon", html: row("fp-a") } ],
      sections: [
        { key: "pokemon", parent: null, total: 4, unique: 2, rows: [ "fp-a" ], html: typeSection("pokemon", []) },
        { key: "trainer-item", parent: "trainer", total: 7, unique: 3 },
        // Listed after its child on purpose, and with numbers, so a group writing into the first
        // count it finds below it would overwrite the child's.
        { key: "trainer", parent: null, total: 9, unique: 9 }
      ]
    }))

    const counts = (key) => {
      const section = rendered.element.querySelector(`[data-section-key="${key}"]`)
      return [ section.querySelector("[data-section-total]").textContent, section.querySelector("[data-section-unique]").textContent ]
    }
    expect(counts("pokemon")).toEqual([ "4", "2" ])
    expect(counts("trainer-item")).toEqual([ "7", "3" ])
  })

  test("writes a set section's total and noun", async () => {
    const rendered = await mount(page([ setSection("set-1", [ row("printing:11", { fingerprint: "fp-x", printing: true }) ], { total: 2, noun: "cards" }) ]), controllers)

    await apply(rendered, answer({
      fingerprintKey: "fp-x",
      rows: [ { key: "printing:11", section: "set-1", html: row("printing:11", { fingerprint: "fp-x", printing: true }) } ],
      sections: [ { key: "set-1", parent: null, total: 1, noun: "card", rows: [ "printing:11" ], html: setSection("set-1", []) } ]
    }))

    const heading = rendered.element.querySelector('[data-section-key="set-1"] h2')
    expect(heading.querySelector("[data-section-total]").textContent).toBe("1")
    expect(heading.querySelector("[data-section-noun]").textContent).toBe("card")
  })

  test("writes the deck total and announces the Proxies flag", async () => {
    const rendered = await mount(page([ typeSection("pokemon", [ row("fp-a") ]) ], { total: 10 }), controllers)
    const changes = captureEvents(document, "deck-proxies:changed")

    await apply(rendered, answer({
      fingerprintKey: "fp-a",
      rows: [ { key: "fp-a", section: "pokemon", html: row("fp-a") } ],
      sections: [ { key: "pokemon", parent: null, total: 1, unique: 1, rows: [ "fp-a" ], html: typeSection("pokemon", []) } ],
      deck: { has_proxies: true, total: 13 }
    }))

    expect(rendered.element.querySelector('[data-deck-rows-target="total"]').textContent).toBe("13")
    expect(changes.map((event) => event.detail)).toEqual([ { hasProxies: true } ])
  })

  test("re-expands the disclosures that were open in the rows it replaced, and only those", async () => {
    const rendered = await mount(page([ typeSection("pokemon", [ row("fp-a", { disclosure: true }), row("fp-b", { disclosure: true }) ]) ]), controllers)
    const toggle = rendered.element.querySelector('[aria-controls="deck-printings-fp-a"]')
    toggle.setAttribute("aria-expanded", "true")
    rendered.element.querySelector("#deck-printings-fp-a").hidden = false

    const section = { key: "pokemon", parent: null, total: 2, unique: 2, rows: [ "fp-a", "fp-b" ], html: typeSection("pokemon", []) }
    await apply(rendered, answer({ fingerprintKey: "fp-a", rows: [ { key: "fp-a", section: "pokemon", html: row("fp-a", { disclosure: true, label: "new" }) } ], sections: [ section ] }))

    const replaced = rendered.element.querySelector('[data-row-key="fp-a"]')
    expect(replaced.querySelector(".label").textContent).toBe("new")
    expect(replaced.querySelector(".deck-printings-toggle").getAttribute("aria-expanded")).toBe("true")
    expect(replaced.querySelector("#deck-printings-fp-a").hidden).toBe(false)
    expect(rendered.element.querySelector('[aria-controls="deck-printings-fp-b"]').getAttribute("aria-expanded")).toBe("false")
    expect(rendered.element.querySelector("#deck-printings-fp-b").hidden).toBe(true)
  })

  test("gives focus back to the button carrying the same focus key", async () => {
    const reply = answer({
      fingerprintKey: "fp-a",
      rows: [ { key: "fp-a", section: "pokemon", html: row("fp-a", { label: "new" }) } ],
      sections: [ { key: "pokemon", parent: null, total: 1, unique: 1, rows: [ "fp-a" ], html: typeSection("pokemon", []) } ]
    })
    stubFetch(jsonResponse(reply))
    const { element } = await mount(page([ typeSection("pokemon", [ row("fp-a") ]) ]), controllers)
    const button = element.querySelector('[data-focus-key="qty-plus-fp-a"]')
    button.focus()

    button.click()
    await settle()

    const replacement = element.querySelector('[data-focus-key="qty-plus-fp-a"]')
    expect(replacement).not.toBe(button)
    expect(document.activeElement).toBe(replacement)
  })

  test("does not focus the replacement when it is disabled", async () => {
    const reply = answer({
      fingerprintKey: "fp-a",
      rows: [ { key: "fp-a", section: "pokemon", html: row("fp-a", { disabled: true }) } ],
      sections: [ { key: "pokemon", parent: null, total: 1, unique: 1, rows: [ "fp-a" ], html: typeSection("pokemon", []) } ]
    })
    stubFetch(jsonResponse(reply))
    const { element } = await mount(page([ typeSection("pokemon", [ row("fp-a") ]) ]), controllers)
    const button = element.querySelector('[data-focus-key="qty-plus-fp-a"]')
    button.focus()

    // jsdom already refuses to focus a disabled button, so the call itself is what is watched.
    const focus = vi.spyOn(HTMLElement.prototype, "focus")

    button.click()
    await settle()

    expect(focus.mock.contexts).not.toContain(element.querySelector('[data-focus-key="qty-plus-fp-a"]'))
  })

  test("ignores a second click while a write is in flight, and takes the next one after", async () => {
    let release
    const reply = answer({
      fingerprintKey: "fp-a",
      rows: [ { key: "fp-a", section: "pokemon", html: row("fp-a") } ],
      sections: [ { key: "pokemon", parent: null, total: 1, unique: 1, rows: [ "fp-a" ], html: typeSection("pokemon", []) } ]
    })
    stubFetch(() => new Promise((resolve) => { release = () => resolve(jsonResponse(reply)) }), jsonResponse(reply))
    const { element } = await mount(page([ typeSection("pokemon", [ row("fp-a") ]) ]), controllers)

    element.querySelector('[data-row-key="fp-a"] button').click()
    await settle()
    expect(element.querySelector(".deck-sections").getAttribute("aria-busy")).toBe("true")
    element.querySelector('[data-row-key="fp-a"] button').click()
    await settle()
    expect(requests()).toHaveLength(1)

    release()
    await settle()
    expect(element.querySelector(".deck-sections").hasAttribute("aria-busy")).toBe(false)
    element.querySelector('[data-row-key="fp-a"] button').click()
    await settle()
    expect(requests()).toHaveLength(2)
  })

  test("applies nothing when the write is refused, flashes the server's reason and frees the next click", async () => {
    const reply = answer({
      fingerprintKey: "fp-a",
      rows: [],
      sections: [],
      deck: { has_proxies: true, total: 0 }
    })
    stubFetch(jsonResponse({ errors: [ "no proxy left to back" ] }, { status: 422 }), jsonResponse(reply))
    const rendered = await mount(page([ typeSection("pokemon", [ row("fp-a") ], { total: 1, unique: 1 }) ], { total: 10 }), controllers)
    const { element } = rendered
    const changes = captureEvents(document, "deck-proxies:changed")
    // apply(null) would throw inside an async action, where Stimulus never sees it: the spy is what
    // says it was not called.
    const applied = vi.spyOn(rendered.controller("deck-rows"), "apply")

    element.querySelector('[data-row-key="fp-a"] button').click()
    await settle()

    expect(applied).not.toHaveBeenCalled()
    expect(flashMessages()).toEqual([ { text: "no proxy left to back", kind: "alert" } ])
    expect(element.querySelector('[data-row-key="fp-a"]')).not.toBeNull()
    expect(sectionKeys(element)).toEqual([ "pokemon" ])
    expect(element.querySelector('[data-deck-rows-target="total"]').textContent).toBe("10")
    expect(changes).toEqual([])

    element.querySelector('[data-row-key="fp-a"] button').click()
    await settle()
    expect(requests()).toHaveLength(2)
  })

  // Stimulus hands an absent param over as undefined and an empty one as "" (JSON.parse("") throws,
  // so the raw string comes back): neither may reach the server as a body, `""` included.
  test("sends no body when the button carries none, or an empty one", async () => {
    const fetch = stubFetch(
      jsonResponse(answer({ fingerprintKey: "fp-a", rows: [], sections: [] })),
      jsonResponse(answer({ fingerprintKey: "fp-a", rows: [], sections: [] }))
    )
    // Outside the rows, which the first answer takes away.
    const buttons = `<button id="none" data-action="deck-rows#write"
        data-deck-rows-url-param="/api/decks/k/cards/1/collection_copy" data-deck-rows-method-param="POST"
        data-deck-rows-failure-param="Couldn't add it">+ add</button><button id="empty" data-action="deck-rows#write"
        data-deck-rows-url-param="/api/decks/k/cards/1/collection_copy" data-deck-rows-method-param="POST"
        data-deck-rows-body-param="" data-deck-rows-failure-param="Couldn't add it">+ add</button>`
    const { element } = await mount(page([ typeSection("pokemon", [ row("fp-a") ]) ], { inner: buttons }), controllers)

    element.querySelector("#none").click()
    await settle()
    element.querySelector("#empty").click()
    await settle()

    expect(requests()).toMatchObject([ { url: "/api/decks/k/cards/1/collection_copy", method: "POST" }, { method: "POST" } ])
    expect(fetch.mock.calls.map(([ , init ]) => init.body)).toEqual([ undefined, undefined ])
  })

  test("refuses an answer that places a row in a section it neither holds nor sends", async () => {
    const rendered = await mount(page([ typeSection("pokemon", [ row("fp-a") ]) ]), controllers)

    expect(() => rendered.controller("deck-rows").apply(answer({
      fingerprintKey: "fp-e",
      rows: [ { key: "fp-e", section: "energy", html: row("fp-e") } ],
      sections: [ { key: "pokemon", parent: null, total: 1, unique: 1 }, { key: "energy", parent: null, total: 1, unique: 1 } ]
    }))).toThrow('deck-rows: the answer places a row in section "energy" without its html')
  })

  test("removes the row of a fingerprint that left the deck from a section another card keeps", async () => {
    const rendered = await mount(page([ typeSection("pokemon", [ row("fp-a"), row("fp-b") ], { total: 2, unique: 2 }) ]), controllers)
    const kept = rendered.element.querySelector('[data-row-key="fp-a"]')

    await apply(rendered, answer({
      fingerprintKey: "fp-b",
      rows: [],
      sections: [ { key: "pokemon", parent: null, total: 1, unique: 1 } ]
    }))

    expect(rowKeys(listOf(rendered.element, "pokemon"))).toEqual([ "fp-a" ])
    expect(rendered.element.querySelector('[data-row-key="fp-a"]')).toBe(kept)
    expect(rendered.element.querySelector('[data-section-key="pokemon"] [data-section-total]').textContent).toBe("1")
  })

  // A type section's answer carries no noun, and a group's carries null counts: what an answer leaves
  // out is not written, whatever span the heading holds.
  test("writes only the counts the answer carries", async () => {
    const heading = (key) => `<div class="deck-section" data-section-key="${key}">
      <h2>${key} <span data-section-total>2</span> <span data-section-unique>2</span> <span data-section-noun>cards</span></h2>
      <ul class="deck-card-list">${row(`fp-${key}`)}</ul></div>`
    const rendered = await mount(page([ heading("pokemon"), heading("trainer") ]), controllers)

    await apply(rendered, answer({
      fingerprintKey: "fp-pokemon",
      rows: [ { key: "fp-pokemon", section: "pokemon", html: row("fp-pokemon") } ],
      sections: [
        { key: "pokemon", parent: null, total: 4, unique: 3, rows: [ "fp-pokemon" ], html: heading("pokemon") },
        { key: "trainer", parent: null, total: null, unique: null }
      ]
    }))

    const spans = (key) => Array.from(rendered.element.querySelectorAll(`[data-section-key="${key}"] h2 span`), (span) => span.textContent)
    expect(spans("pokemon")).toEqual([ "4", "3", "cards" ])
    expect(spans("trainer")).toEqual([ "2", "2", "cards" ])
  })

  test("keeps a disclosure closed in a replaced row while reopening the one that was open", async () => {
    const card = (label) => `<li class="deck-fingerprint" data-row-key="fp-a" data-fingerprint-key="fp-a">
      <div class="deck-card-line"><span class="label">${label}</span>
        <button class="deck-printings-toggle" aria-expanded="false" aria-controls="deck-printings-fp-a">▸</button></div>
      <ul class="deck-printing-list" id="deck-printings-fp-a" hidden>
        <li class="deck-printing-others">
          <button class="deck-printings-others-toggle" aria-expanded="false" aria-controls="deck-printings-others-fp-a">Other</button>
          <ul class="deck-printing-list" id="deck-printings-others-fp-a" hidden></ul>
        </li>
      </ul></li>`
    const rendered = await mount(page([ typeSection("pokemon", [ card("old") ]) ]), controllers)
    rendered.element.querySelector('[aria-controls="deck-printings-fp-a"]').setAttribute("aria-expanded", "true")
    rendered.element.querySelector("#deck-printings-fp-a").hidden = false

    await apply(rendered, answer({
      fingerprintKey: "fp-a",
      rows: [ { key: "fp-a", section: "pokemon", html: card("new") } ],
      sections: [ { key: "pokemon", parent: null, total: 1, unique: 1, rows: [ "fp-a" ], html: typeSection("pokemon", []) } ]
    }))

    expect(rendered.element.querySelector(".label").textContent).toBe("new")
    expect(rendered.element.querySelector("#deck-printings-fp-a").hidden).toBe(false)
    expect(rendered.element.querySelector('[aria-controls="deck-printings-others-fp-a"]').getAttribute("aria-expanded")).toBe("false")
    expect(rendered.element.querySelector("#deck-printings-others-fp-a").hidden).toBe(true)
  })

  test("leaves the focus alone when it sits outside the deck list", async () => {
    const reply = answer({
      fingerprintKey: "fp-a",
      rows: [ { key: "fp-a", section: "pokemon", html: row("fp-a", { label: "new" }) } ],
      sections: [ { key: "pokemon", parent: null, total: 1, unique: 1, rows: [ "fp-a" ], html: typeSection("pokemon", []) } ]
    })
    const rendered = await mount(page([ typeSection("pokemon", [ row("fp-a") ]) ]), controllers)
    document.body.insertAdjacentHTML("beforeend", `<button id="elsewhere" data-focus-key="qty-plus-fp-a">elsewhere</button>`)
    const elsewhere = document.getElementById("elsewhere")
    elsewhere.focus()

    await apply(rendered, reply)

    expect(document.activeElement).toBe(elsewhere)
  })

  test("sends the add card search hands it and applies the answer, with no reload", async () => {
    const reply = answer({
      fingerprintKey: "fp-n",
      rows: [ { key: "fp-n", section: "pokemon", html: row("fp-n") } ],
      sections: [ { key: "pokemon", parent: null, total: 2, unique: 2, rows: [ "fp-a", "fp-n" ], html: typeSection("pokemon", []) } ],
      deck: { has_proxies: false, total: 11 }
    })
    stubFetch(jsonResponse(reply, { status: 201 }))
    const { element } = await mount(
      page([ typeSection("pokemon", [ row("fp-a") ]) ], { inner: searchFragment }),
      { ...controllers, "card-search": CardSearchController }
    )

    element.querySelector(".card-search-add-btn").click()
    await settle()

    expect(requests()).toMatchObject([ { url: "/api/decks/k/cards?group=type", method: "POST", body: { deck_card: { card_id: "99", quantity: 1 } } } ])
    expect(rowKeys(listOf(element, "pokemon"))).toEqual([ "fp-a", "fp-n" ])
    expect(element.querySelector('[data-deck-rows-target="total"]').textContent).toBe("11")
    expect(window.Turbo.visit).not.toHaveBeenCalled()
  })

  // Reproduced before the add went through here: a stepper's older answer landed after the add's
  // and overwrote it — the heading said 3 over a row of 4, the total 18 against the server's 19.
  test("a search add waits for the write in flight, then is sent and applied after it", async () => {
    let release
    const step = answer({
      fingerprintKey: "fp-a",
      rows: [ { key: "fp-a", section: "pokemon", html: row("fp-a", { label: "stepped" }) } ],
      sections: [ { key: "pokemon", parent: null, total: 3, unique: 1, rows: [ "fp-a" ], html: typeSection("pokemon", []) } ],
      deck: { has_proxies: false, total: 18 }
    })
    const added = answer({
      fingerprintKey: "fp-a",
      rows: [ { key: "fp-a", section: "pokemon", html: row("fp-a", { label: "added" }) } ],
      sections: [ { key: "pokemon", parent: null, total: 4, unique: 1, rows: [ "fp-a" ], html: typeSection("pokemon", []) } ],
      deck: { has_proxies: false, total: 19 }
    })
    stubFetch(() => new Promise((resolve) => { release = () => resolve(jsonResponse(step)) }), jsonResponse(added, { status: 201 }))
    const { element } = await mount(
      page([ typeSection("pokemon", [ row("fp-a") ], { total: 2, unique: 1 }) ], { inner: searchFragment }),
      { ...controllers, "card-search": CardSearchController }
    )
    const sections = element.querySelector(".deck-sections")

    element.querySelector('[data-row-key="fp-a"] button').click()
    await settle()
    // The stepper click, outside the search, closed its results: the member searches again.
    element.querySelector("[data-card-search-target=results]").innerHTML = addButton
    await settle()
    element.querySelector(".card-search-add-btn").click()
    await settle()

    expect(requests()).toHaveLength(1)
    expect(sections.getAttribute("aria-busy")).toBe("true")

    release()
    await settle()

    expect(requests().map((request) => request.method)).toEqual([ "PATCH", "POST" ])
    expect(element.querySelector('[data-row-key="fp-a"] .label').textContent).toBe("added")
    expect(element.querySelector('[data-section-key="pokemon"] [data-section-total]').textContent).toBe("4")
    expect(element.querySelector('[data-deck-rows-target="total"]').textContent).toBe("19")
    expect(sections.hasAttribute("aria-busy")).toBe(false)
  })

  test("a stepper click while a search add is in flight is ignored, and the add is applied", async () => {
    let release
    const added = answer({
      fingerprintKey: "fp-n",
      rows: [ { key: "fp-n", section: "pokemon", html: row("fp-n") } ],
      sections: [ { key: "pokemon", parent: null, total: 2, unique: 2, rows: [ "fp-a", "fp-n" ], html: typeSection("pokemon", []) } ],
      deck: { has_proxies: false, total: 11 }
    })
    stubFetch(() => new Promise((resolve) => { release = () => resolve(jsonResponse(added, { status: 201 })) }))
    const { element } = await mount(
      page([ typeSection("pokemon", [ row("fp-a") ]) ], { inner: searchFragment }),
      { ...controllers, "card-search": CardSearchController }
    )

    element.querySelector(".card-search-add-btn").click()
    await settle()
    element.querySelector('[data-row-key="fp-a"] button').click()
    await settle()
    expect(requests()).toHaveLength(1)
    expect(element.querySelector(".deck-sections").getAttribute("aria-busy")).toBe("true")

    release()
    await settle()
    expect(rowKeys(listOf(element, "pokemon"))).toEqual([ "fp-a", "fp-n" ])
  })
})

// The "Other printings" list as the page renders it (`pending`: its count and the request that
// fetches it, the list empty) or as a write's answer renders it (the sub-rows already inside, the
// toggle a plain disclosure). `fetchAction` keeps the fetching action on a list that is not
// pending, which no server render produces: it is what shows that the pending mark alone decides.
function othersRow(key, { pending = true, fetchAction = pending, label = key, items = "" } = {}) {
  const id = `deck-printings-others-${key}`
  const fetch = fetchAction
    ? ` data-action="disclosure#toggle deck-rows#others" data-deck-rows-url-param="/api/decks/k/cards/1/other_printings"
        data-deck-rows-failure-param="Couldn't load the other printings"`
    : ` data-action="disclosure#toggle"`
  return `<li class="deck-fingerprint" data-row-key="${key}" data-fingerprint-key="${key}">
    <div class="deck-card-line"><span class="label">${label}</span>${writeButton(`qty-plus-${key}`)}</div>
    <ul class="deck-printing-list" id="deck-printings-${key}">
      <li class="deck-printing-others">
        <button class="deck-printings-others-toggle" aria-expanded="false" aria-controls="${id}"${fetch}>Other printings (2)</button>
        <ul class="deck-printing-list" id="${id}" hidden${pending ? " data-deck-rows-pending" : ""}>${items}</ul>
      </li>
    </ul>
  </li>`
}

const subRows = `<li class="deck-printing-row"><span class="deck-card-set">TWM 3</span></li>
  <li class="deck-printing-row"><span class="deck-card-set">POR 3</span></li>`

const withDisclosure = { ...controllers, disclosure: DisclosureController }

async function mountOthers(rows = [ othersRow("fp-a") ]) {
  return mount(page([ typeSection("pokemon", rows) ], { extraControllers: " disclosure" }), withDisclosure)
}

function setLabels(root) {
  return Array.from(root.querySelectorAll("#deck-printings-others-fp-a > li.deck-printing-row .deck-card-set"), (node) => node.textContent)
}

describe("deck_rows_controller — other printings, fetched on first open", () => {
  test("fetches the list the first time it opens, inserts the server's sub-rows, and never again", async () => {
    stubFetch(jsonResponse({ fingerprint_key: "fp-a", html: subRows }))
    const { element } = await mountOthers()
    const toggle = element.querySelector(".deck-printings-others-toggle")
    const list = element.querySelector("#deck-printings-others-fp-a")

    toggle.click()
    await settle()

    expect(requests()).toMatchObject([ { url: "/api/decks/k/cards/1/other_printings", method: "GET", body: undefined } ])
    expect(setLabels(element)).toEqual([ "TWM 3", "POR 3" ])
    expect(list.hidden).toBe(false)
    expect(list.hasAttribute("data-deck-rows-pending")).toBe(false)
    expect(list.hasAttribute("aria-busy")).toBe(false)

    toggle.click()
    await settle()
    toggle.click()
    await settle()

    expect(requests()).toHaveLength(1)
    expect(list.hidden).toBe(false)
    expect(setLabels(element)).toEqual([ "TWM 3", "POR 3" ])
    expect(flashMessages()).toEqual([])
  })

  // Closing it again while the answer is on its way must not send a second request either.
  test("sends one request when the list is closed and reopened before the answer", async () => {
    let release
    stubFetch(() => new Promise((resolve) => { release = () => resolve(jsonResponse({ fingerprint_key: "fp-a", html: subRows })) }))
    const { element } = await mountOthers()
    const toggle = element.querySelector(".deck-printings-others-toggle")

    toggle.click()
    await settle()
    expect(element.querySelector("#deck-printings-others-fp-a").getAttribute("aria-busy")).toBe("true")
    toggle.click()
    toggle.click()
    await settle()
    release()
    await settle()

    expect(requests()).toHaveLength(1)
    expect(setLabels(element)).toEqual([ "TWM 3", "POR 3" ])
  })

  test("a list a write's answer rendered whole is never fetched", async () => {
    const { element } = await mountOthers([ othersRow("fp-a", { pending: false, fetchAction: true, items: subRows }) ])

    element.querySelector(".deck-printings-others-toggle").click()
    await settle()

    expect(requests()).toEqual([])
    expect(setLabels(element)).toEqual([ "TWM 3", "POR 3" ])
  })

  test("a failed fetch flashes, closes the list again, and the next open retries", async () => {
    stubFetch(jsonResponse({ errors: [ "Not found" ] }, { status: 404 }), jsonResponse({ fingerprint_key: "fp-a", html: subRows }))
    const { element } = await mountOthers()
    const toggle = element.querySelector(".deck-printings-others-toggle")
    const list = element.querySelector("#deck-printings-others-fp-a")

    toggle.click()
    await settle()

    expect(flashMessages()).toEqual([ { text: "Not found", kind: "alert" } ])
    expect(toggle.getAttribute("aria-expanded")).toBe("false")
    expect(list.hidden).toBe(true)
    expect(list.hasAttribute("data-deck-rows-pending")).toBe(true)
    expect(list.hasAttribute("aria-busy")).toBe(false)
    expect(setLabels(element)).toEqual([])

    toggle.click()
    await settle()

    expect(requests()).toHaveLength(2)
    expect(setLabels(element)).toEqual([ "TWM 3", "POR 3" ])
    expect(list.hidden).toBe(false)
  })

  // A write answered while the fetch was in flight re-rendered the row with its list whole and
  // current; the fetched one, computed before the write, has nowhere left to go.
  test("drops a fetched list whose row a write replaced in the meantime", async () => {
    let release
    stubFetch(() => new Promise((resolve) => { release = () => resolve(jsonResponse({ fingerprint_key: "fp-a", html: subRows })) }))
    const rendered = await mountOthers()
    const { element } = rendered
    element.querySelector(".deck-printings-others-toggle").click()
    await settle()

    const fresh = `<li class="deck-printing-row"><span class="deck-card-set">TWM 3</span></li>`
    await apply(rendered, answer({
      fingerprintKey: "fp-a",
      rows: [ { key: "fp-a", section: "pokemon", html: othersRow("fp-a", { pending: false, label: "after", items: fresh }) } ],
      sections: [ { key: "pokemon", parent: null, total: 1, unique: 1, rows: [ "fp-a" ], html: typeSection("pokemon", []) } ]
    }))
    release()
    await settle()

    expect(element.querySelector(".label").textContent).toBe("after")
    expect(setLabels(element)).toEqual([ "TWM 3" ])
    expect(element.querySelector("#deck-printings-others-fp-a").hidden).toBe(false)
    expect(element.querySelectorAll("#deck-printings-others-fp-a")).toHaveLength(1)
  })
})
