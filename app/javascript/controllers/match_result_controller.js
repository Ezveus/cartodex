import { Controller } from "@hotwired/stimulus"

// Drives the BO1/BO3 format toggle, the overall result buttons, and the
// per-game BO3 score selector. For a BO3 with a score, the overall result is
// derived from the games and the manual result buttons are locked. Keeps three
// hidden inputs (match_format, result, score) in sync so the surrounding form
// or the result modal can read them.
export default class extends Controller {
  static targets = [
    "matchFormatInput", "resultInput", "scoreInput",
    "formatBtn", "resultBtn", "resultButtons",
    "gameBtn", "gameRow", "scoreSection"
  ]

  connect() {
    this.#sync()
  }

  selectFormat(event) {
    this.matchFormatInputTarget.value = event.currentTarget.dataset.format
    if (event.currentTarget.dataset.format !== "bo3") this.scoreInputTarget.value = ""
    this.#sync()
  }

  selectResult(event) {
    if (event.currentTarget.disabled) return
    this.resultInputTarget.value = event.currentTarget.dataset.result
    this.#sync()
  }

  selectGame(event) {
    const btn = event.currentTarget
    if (btn.disabled) return

    const i = parseInt(btn.dataset.gameIndex, 10)
    const outcome = btn.dataset.game
    const current = this.#games()

    // Re-clicking the active game deselects it (and any games after it).
    const games = current.slice(0, i)
    if (current[i] !== outcome) games[i] = outcome

    this.scoreInputTarget.value = games.join("")
    this.#sync()
  }

  clearScore() {
    this.scoreInputTarget.value = ""
    this.#sync()
  }

  // Called by the result modal when it closes, to reset to a fresh BO1 entry.
  reset() {
    this.matchFormatInputTarget.value = "bo1"
    this.resultInputTarget.value = ""
    this.scoreInputTarget.value = ""
    this.#sync()
  }

  // Mirrors DeckResult.result_from_score: maps a score to the overall result,
  // or null when the games do not yet determine a winner.
  deriveResult(score) {
    const g = score.split("")
    if (g.includes("D")) return "draw"
    if (g.includes("T")) return "timeout"
    if (g.filter(x => x === "W").length >= 2) return "win"
    if (g.filter(x => x === "L").length >= 2) return "loss"
    return null
  }

  // --- Private ---

  #games() {
    return (this.scoreInputTarget.value || "").split("").filter(Boolean)
  }

  #sync() {
    const format = this.matchFormatInputTarget.value || "bo1"
    const isBo3 = format === "bo3"

    this.formatBtnTargets.forEach(b => b.classList.toggle("active", b.dataset.format === format))
    if (this.hasScoreSectionTarget) this.scoreSectionTarget.style.display = isBo3 ? "" : "none"

    if (!isBo3) this.scoreInputTarget.value = ""
    const games = this.#games()

    this.gameBtnTargets.forEach(btn => {
      const i = parseInt(btn.dataset.gameIndex, 10)
      btn.disabled = !this.#gameEnabled(games, i)
      btn.classList.toggle("active", games[i] === btn.dataset.game)
    })

    const score = isBo3 ? games.join("") : ""
    const locked = Boolean(score)
    if (locked) {
      const derived = this.deriveResult(score)
      if (derived) this.resultInputTarget.value = derived
    }
    this.#setResultButtons(this.resultInputTarget.value, locked)
  }

  #gameEnabled(games, i) {
    if (i === 0) return true
    if (games[i - 1] === undefined) return false
    return this.deriveResult(games.slice(0, i).join("")) === null
  }

  #setResultButtons(active, locked) {
    this.resultBtnTargets.forEach(b => {
      b.classList.toggle("active", b.dataset.result === active)
      b.disabled = locked
      b.classList.toggle("locked", locked)
    })
  }
}
