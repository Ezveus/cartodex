import { Controller } from "@hotwired/stimulus"

// A tournament's date decides which Standard it was played under, so the pool select
// follows the date field. Without this the select keeps whatever the server pre-selected
// for the date the form was first rendered with — which on a new tournament is today —
// and someone recording last month's event silently anchors it to the current Standard,
// discovering the mistake only on a later edit, from the stale-anchor notice.
//
// It stops following once the user picks a pool by hand: an explicit choice outranks the
// date, and a subsequent date edit must not quietly undo it.
export default class extends Controller {
  static targets = ["date", "pool"]
  static values = { pools: Array, fallbackId: Number }

  connect() {
    this.overridden = false
  }

  markOverridden() {
    this.overridden = true
  }

  syncFromDate() {
    if (this.overridden) return
    if (!this.hasDateTarget || !this.hasPoolTarget) return

    const id = this.poolForDate(this.dateTarget.value)
    if (id) this.poolTarget.value = String(id)
  }

  // Mirrors StandardPool.at(date): the newest pool already legal on that date. Falls back
  // to what the server itself would have used when the date precedes every pool, so the
  // two never disagree. ISO dates compare correctly as strings, which is what the date
  // input hands us.
  poolForDate(date) {
    if (!date) return this.fallback

    const legal = this.poolsValue
      .filter((pool) => pool.legal_on <= date)
      .sort((a, b) => (a.legal_on < b.legal_on ? 1 : -1))

    return legal.length ? legal[0].id : this.fallback
  }

  get fallback() {
    return this.fallbackIdValue > 0 ? this.fallbackIdValue : null
  }
}
