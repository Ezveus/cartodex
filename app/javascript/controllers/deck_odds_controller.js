import { Controller } from "@hotwired/stimulus"

// Moves every reactive number on /decks/:id/odds without a request.
//
// It does no arithmetic. Each cell carries its whole curve in data-curve, precomputed in Ruby by
// Decks::Odds::Report, and this controller only picks an index out of it: `seen` — turn + effect
// draws + prizes taken — for an accessibility cell, and prizes taken alone for a prize cell, which
// asks about the prize block rather than about how much of the deck has been seen.
//
// A second implementation of the conditional hypergeometric here would be held down by nothing: the
// repo has no JS test infrastructure, only system tests. Formatting is the one thing duplicated, and
// deliberately: `toFixed(2)` here against `format("%.2f")` in Decks::Odds::Formatting, over a number
// that was rounded once, server-side, by Decks::Odds::Report.percent.
export default class extends Controller {
  static targets = ["turn", "effectDraws", "prizesTaken", "seenSummary", "cell", "prizeCell"]
  static values = { maxDraws: Number, maxPrizes: Number, handSize: Number }

  connect() {
    this.render()
  }

  // The six +/− buttons. `field` and `delta` arrive as action params, so one handler serves them all.
  step(event) {
    const { field, delta } = event.params
    const target = this[`${field}Target`]
    target.value = String(this.#clamp(field, this.#value(field) + delta))
    this.render()
  }

  // Also wired to turbo:frame-load on the wrapper: the combination frame's answer ships a cell with
  // its own curve, and the scenario the reader had set has to be re-applied to it.
  render() {
    const drawn = Math.min(this.#value("turn") + this.#value("effectDraws"), this.maxDrawsValue)
    const prizes = this.hasPrizesTakenTarget ? this.#value("prizesTaken") : 0
    const seen = drawn + prizes

    if (this.hasSeenSummaryTarget) {
      const plural = prizes === 1 ? "prize" : "prizes"
      this.seenSummaryTarget.textContent =
        `${this.handSizeValue + seen} cards seen (${this.handSizeValue} hand + ${drawn} drawn + ${prizes} ${plural})`
    }

    this.cellTargets.forEach((cell) => this.#write(cell, seen))
    this.prizeCellTargets.forEach((cell) => this.#write(cell, prizes))
  }

  // Indexing, and nothing more. Clamping against the curve's own length is the last guard: a
  // hand-edited input, or a cell rendered against a deck that has since changed size, must not read
  // past the end and print "undefined %".
  #write(cell, index) {
    const curve = JSON.parse(cell.dataset.curve)
    const value = curve[Math.min(Math.max(index, 0), curve.length - 1)]
    cell.textContent = `${value.toFixed(2)} %`
  }

  // Reads an input, clamping it and writing the clamped value back, so the field never shows a number
  // the page is not using. Assigning `.value` fires no input event, so this cannot loop.
  #value(field) {
    const target = this[`${field}Target`]
    const clamped = this.#clamp(field, Number(target.value))
    if (String(clamped) !== target.value) target.value = String(clamped)
    return clamped
  }

  // The two axes have different ceilings, and that is the whole reason prizes keep a control of their
  // own: p <= 6 while d <= N - 13. A merged "+X cards gained" stepper could clamp neither correctly.
  #clamp(field, value) {
    if (!Number.isFinite(value)) return field === "turn" ? 1 : 0
    if (field === "prizesTaken") return Math.min(Math.max(value, 0), this.maxPrizesValue)

    return Math.min(Math.max(value, field === "turn" ? 1 : 0), this.maxDrawsValue)
  }
}
