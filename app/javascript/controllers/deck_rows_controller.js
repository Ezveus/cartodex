import { Controller } from "@hotwired/stimulus"
import { requestJson } from "helpers/api"

// Applies the server's answer to a deck write: the fingerprint's rows, their sections, every
// section's counts and the deck's total. It decides nothing — no quantity, no bound, no order.
// Each button carries the request it sends as action params, and every placement is read off the
// answer (a section's ordered row keys, the page order of the sections), because a second copy
// of those rules in the browser would be held down by nothing and drift from the server's.
//
// The answer's shape is the frozen contract in
// docs/superpowers/plans/2026-10-24-deck-fingerprint-rows.md ("API" and "DOM").
export default class extends Controller {
  static targets = ["total", "sections"]

  async write({ params: { url, method, body, failure } }) {
    // A second click before the answer would be computed by the server against a state the page
    // has not shown yet, and the two answers could then land in either order.
    if (this.busy) return
    this.busy = true
    // Says to assistive technology — and to the system tests, which must not read a row the answer
    // is about to replace — that the list is being rewritten.
    this.sectionsTarget.setAttribute("aria-busy", "true")

    try {
      const data = await requestJson(url, { method, body: body === "" ? undefined : body, failure })
      if (data) this.apply(data)
    } finally {
      this.busy = false
      this.sectionsTarget.removeAttribute("aria-busy")
    }
  }

  added({ detail }) {
    this.apply(detail)
  }

  apply(data) {
    const sections = new Map(data.sections.map((section) => [ section.key, section ]))
    const replaced = this.#fingerprintRows(data.fingerprint_key)
    const expanded = replaced.flatMap((row) =>
      Array.from(row.querySelectorAll('[aria-expanded="true"]'), (toggle) => toggle.getAttribute("aria-controls")))
    // Replacing the row drops the focused button with it, which leaves a keyboard user at the top
    // of the document after every step.
    const focusKey = this.element.contains(document.activeElement) ? document.activeElement.dataset.focusKey : undefined

    const kept = new Set(data.rows.map((row) => row.key))
    for (const row of replaced) {
      if (!kept.has(row.dataset.rowKey)) row.remove()
    }

    for (const row of data.rows) this.#place(row, sections, data.sections)

    for (const element of this.#all("[data-section-key]")) {
      if (!sections.has(element.dataset.sectionKey)) element.remove()
    }

    for (const section of data.sections) this.#writeCounts(section)

    if (this.hasTotalTarget) this.totalTarget.textContent = data.deck.total
    this.dispatch("changed", { prefix: "deck-proxies", detail: { hasProxies: data.deck.has_proxies } })

    for (const id of expanded) this.#expand(id)
    if (focusKey) {
      const target = this.#find(this.element, "data-focus-key", focusKey)
      if (target && !target.disabled) target.focus()
    }
  }

  #place(row, sections, order) {
    const element = this.#build(row.html)
    const current = this.#find(this.sectionsTarget, "data-row-key", row.key)
    if (current) {
      current.replaceWith(element)
      return
    }

    const section = this.#section(row.section, sections, order)
    const list = section.querySelector(":scope > ul.deck-card-list")
    const keys = sections.get(row.section).rows
    const next = keys.slice(keys.indexOf(row.key) + 1)
      .map((key) => this.#find(list, "data-row-key", key))
      .find(Boolean)
    list.insertBefore(element, next ?? null)
  }

  // The section a row belongs in, built from its empty shell — and its parent first — when the page
  // does not hold it yet. It goes before the first section after it in the answer's order, under the
  // same parent, that the page already holds.
  #section(key, sections, order) {
    const existing = this.#find(this.sectionsTarget, "data-section-key", key)
    if (existing) return existing

    const entry = sections.get(key)
    if (!entry?.html) throw new Error(`deck-rows: the answer places a row in section "${key}" without its html`)

    const parent = entry.parent ?? null
    const container = parent ? this.#section(parent, sections, order) : this.sectionsTarget
    const next = order.slice(order.indexOf(entry) + 1)
      .filter((candidate) => (candidate.parent ?? null) === parent)
      .map((candidate) => this.#find(container, "data-section-key", candidate.key))
      .find((element) => element?.parentElement === container)

    const element = this.#build(entry.html)
    container.insertBefore(element, next ?? null)
    return element
  }

  // A Trainer group holds its subsections, whose headings carry counts of their own: a section's
  // count is the one no nearer section owns.
  #writeCounts(section) {
    const element = this.#find(this.sectionsTarget, "data-section-key", section.key)
    if (!element) return

    for (const [ attribute, value ] of [ [ "data-section-total", section.total ], [ "data-section-unique", section.unique ], [ "data-section-noun", section.noun ] ]) {
      if (value === null || value === undefined) continue
      const span = Array.from(element.querySelectorAll(`[${attribute}]`))
        .find((candidate) => candidate.closest("[data-section-key]") === element)
      if (span) span.textContent = value
    }
  }

  #expand(id) {
    const toggle = this.#find(this.sectionsTarget, "aria-controls", id)
    const controlled = document.getElementById(id)
    if (!toggle || !controlled) return

    toggle.setAttribute("aria-expanded", "true")
    controlled.hidden = false
  }

  #fingerprintRows(key) {
    return this.#all("[data-row-key][data-fingerprint-key]")
      .filter((row) => row.dataset.fingerprintKey === key)
  }

  #all(selector) {
    return Array.from(this.sectionsTarget.querySelectorAll(selector))
  }

  // Compared in JavaScript rather than interpolated into a selector, so no key can be read as
  // selector syntax.
  #find(root, attribute, value) {
    return Array.from(root.querySelectorAll(`[${attribute}]`))
      .find((element) => element.getAttribute(attribute) === value) ?? null
  }

  #build(html) {
    const template = document.createElement("template")
    template.innerHTML = html.trim()
    return template.content.firstElementChild
  }
}
