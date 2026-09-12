import { Controller } from "@hotwired/stimulus"

// Composes up to four disjoint groups out of the deck's own card groups and asks the server for the
// combination's curve.
//
// It holds no state of its own: the assignment is read back off the frame on every click, so a frame
// load is the only thing that has to be right for the next click to be. Everything else — the bucket
// cap, the chips, the group names — is rendered by Decks::Odds::ComboFrame, in one place. And no
// mathematics happens here: the answer arrives as a curve and Decks::Odds::Cell is what reads it.
//
// Greying out a card already used is a convenience and not the guarantee. Decks::Odds::Combo
// re-checks disjointness on the server, because the param is a URL and disjointness is what lets
// Deal add bucket sizes rather than compute a set union: a param that broke it would not raise, it
// would answer with a wrong number.
//
// The two separators are Decks::Odds::Combo::CARD_SEPARATOR and BUCKET_SEPARATOR, spelled again
// here because JavaScript cannot read a Ruby constant. Neither can appear inside a group key, which
// is 16 hex characters or "card:<id>".
const CARD_SEPARATOR = "."
const BUCKET_SEPARATOR = "|"

// Past the odds page's ration, `rate_limit` raises ActionController::TooManyRequests and Action
// Dispatch answers 429 — with an *empty* body in production, there being no public/429.html for it
// to serve. Turbo's frame loader reads no HTML out of that, so it replaces nothing and dispatches
// no turbo:frame-missing either: the click leaves no trace anywhere on the screen. This is the one
// status that has to be watched for, to unhide a notice ComboCalculator has already rendered.
const TOO_MANY_REQUESTS = 429

export default class extends Controller {
  static targets = ["frame", "state", "picker", "filter", "option", "addCard", "throttled"]
  static values = { url: String, maxBuckets: Number }

  // `state` and not `frame`: Turbo replaces a frame's *children* on navigation and leaves the
  // <turbo-frame> element itself in place, so frameTargetConnected would fire exactly once. The
  // state element is inside the frame and re-connects on every load — which is when the set of used
  // cards has just changed, and the picker, living outside the frame, has to be re-greyed.
  stateTargetConnected() {
    this.#refreshOptions()
    this.throttledTarget.hidden = true
  }

  // Every response to a frame navigation, refused ones included. Only the refusal is handled: a
  // failure that is not a ration — there is none this action can currently produce, the page being
  // a pure function of the decklist — must keep reaching Turbo's own reporting rather than be
  // dressed up as "wait a minute", which would be a lie.
  //
  // Turbo is told not to handle the response, rather than left to no-op on it. It *would* no-op in
  // production, where the refusal has no body; in development the same refusal is the debug
  // exception page, which carries turbo-visit-control="reload" and would replace the whole page
  // with a stack trace. preventDefault is what makes the two environments agree.
  //
  // Nothing is done to the frame's `src`, and that was measured rather than assumed: a reader who
  // retries the very same card once the minute has passed writes the src the frame already holds,
  // and `setAttribute` fires `attributeChangedCallback` whether or not the value changed — so Turbo
  // does navigate again. Clearing it first would be a guard against a bug that is not there.
  answered(event) {
    if (event.detail.fetchResponse.statusCode !== TOO_MANY_REQUESTS) return

    event.preventDefault()
    this.throttledTarget.hidden = false
  }

  openPicker(event) {
    this.#showPicker(Number(event.params.index))
  }

  closePicker() {
    this.pickerBucket = null
    this.pickerTarget.hidden = true
  }

  pick(event) {
    if (this.pickerBucket === null || this.pickerBucket === undefined) return

    const assignment = this.#assignment()
    const key = event.params.key
    if (assignment.flat().includes(key)) return

    assignment[this.pickerBucket] = [...(assignment[this.pickerBucket] || []), key]
    this.closePicker()
    this.#navigate(assignment)
  }

  drop(event) {
    const assignment = this.#assignment()
    const index = Number(event.params.index)
    assignment[index] = (assignment[index] || []).filter((key) => key !== event.params.key)
    this.#navigate(assignment)
  }

  // "New group" opens the picker on a group that does not exist yet, rather than navigating to one.
  // An empty group cannot survive the round trip — the assignment travels as a URL and
  // Decks::Odds::Combo refuses an empty bucket, so dropping it on the way out is the only honest
  // thing to send — which means a group that holds nothing would come straight back as no group at
  // all. A group therefore exists from its first card, and the cap is checked before the picker
  // opens rather than after a card is chosen.
  addBucket() {
    const assignment = this.#assignment()
    if (assignment.length >= this.maxBucketsValue) return

    this.#showPicker(assignment.length)
  }

  removeBucket(event) {
    const assignment = this.#assignment()
    assignment.splice(Number(event.params.index), 1)
    this.#navigate(assignment)
  }

  filter() {
    const needle = this.filterTarget.value.trim().toLowerCase()
    this.optionTargets.forEach((option) => {
      option.hidden = needle.length > 0 && !option.textContent.toLowerCase().includes(needle)
    })
  }

  #showPicker(index) {
    this.pickerBucket = index
    this.filterTarget.value = ""
    this.filter()
    this.pickerTarget.hidden = false
    this.filterTarget.focus()
  }

  // An empty group is dropped on the way out rather than sent: Decks::Odds::Combo refuses one, and
  // "I have not filled this in yet" is not an error worth showing somebody mid-compose.
  #navigate(assignment) {
    const param = assignment
      .filter((bucket) => bucket.length > 0)
      .map((bucket) => bucket.join(CARD_SEPARATOR))
      .join(BUCKET_SEPARATOR)

    this.frameTarget.src = param.length > 0
      ? `${this.urlValue}?combo=${encodeURIComponent(param)}`
      : this.urlValue
  }

  // The assignment as the frame last rendered it. Always at least one group, so there is something
  // to add a card to.
  #assignment() {
    const serialized = this.hasStateTarget ? this.stateTarget.dataset.assignment : ""
    if (!serialized) return [[]]

    return serialized
      .split(BUCKET_SEPARATOR)
      .map((bucket) => bucket.split(CARD_SEPARATOR).filter((key) => key.length > 0))
  }

  #refreshOptions() {
    const used = this.#assignment().flat()
    this.optionTargets.forEach((option) => {
      option.disabled = used.includes(option.dataset.deckComboKeyParam)
    })
  }
}
