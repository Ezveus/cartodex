# Deck fingerprint rows — plan and frozen contract

Spec: `docs/superpowers/specs/2026-10-24-deck-fingerprint-rows-design.md`. Issue #236.

## Frozen contract

### Model

- `Card#fingerprint_key` → `fingerprint.presence || "card:#{id}"`. `Decks::Comparator#build_rows`
  reads it instead of its inline copy.

### Services (lane A)

```ruby
Decks::DeckCardQuantitySetter.call(deck:, card:, quantity: nil, delta: nil)   # exactly one of quantity:/delta:
# - inside serialized_transaction
# - delta: new quantity = the stored row's quantity (0 when there is none) + delta, read inside the
#   transaction — the deck page's steppers send it, so a stale tab cannot turn a − into an increase
# - quantity <= 0 → destroy, nil (unchanged)
# - physical deck and quantity > previous quantity (a new row counts as 0) →
#     owned_copies = Allocations::Backing.greedy(quantity:, current_owned:, available: Availability(excluding_deck).available)
# - otherwise owned_copies = min(owned_copies, quantity) (a decrease drops proxies first)
# - non-physical: owned_copies stays min(owned_copies, quantity) (it is 0)

Decks::CopyMover.call(deck:, from_card:, to_card:) # → Decks::CopyMover::Result(from_deck_card:, to_deck_card:)
# - ArgumentError when from_card == to_card, when the two do not share a present fingerprint,
#   when from_card is not in the deck
# - serialized_transaction: source quantity − 1, owned_copies = min(owned, q − 1), destroyed at 0
#   (from_deck_card nil); target find_or_initialize, quantity + 1, owned_copies =
#   physical ? Backing.greedy(quantity:, current_owned:, available: Availability(to_card, excluding_deck).available) : 0
#   Availability is read AFTER the source write (a freed real of the source is another printing,
#   so it never changes the target's pool, but read after anyway).

Decks::OwnedCopiesSetter.call(deck:, card:, owned_copies: nil, delta: nil)   # exactly one of owned_copies:/delta:
# - delta: new owned = the stored owned_copies + delta, read inside the transaction; same bounds
#   (0..min(quantity, available)) and refusals as an absolute value

Decks::CollectionCopyAdder.call(deck:, card:) # → DeckCard
# - Decks::OwnedCopiesSetter::NotPhysicalError on a non-physical deck
# - ActiveRecord::RecordNotFound when the card is not in the deck
# - ArgumentError "no proxy left to back" when owned_copies >= quantity
# - ArgumentError "a free copy is already available — use the real copy +" when available > owned_copies
# - serialized_transaction: Collections::CardAdder.call(user: deck.user, card:, quantity: 1);
#   then owned_copies = Backing.greedy(quantity:, current_owned:, available: re-read available);
#   ArgumentError (rolling back the collection write) when that is not owned_copies + 1
#   (an over-allocated printing).

Decks::FingerprintStates
  PrintingState = Struct.new(:card, :deck_card, :group, :quantity, :owned_copies, :proxies,
                             :owned, :available, :max_owned, :over_allocated, :move_from,
                             :can_add_to_collection, keyword_init: true)
  # group: :deck (in the deck) | :owned (not in the deck, owned > 0) | :other
  # quantity/owned_copies/proxies: the deck row's, 0 when not in the deck
  # max_owned: physical ? min(quantity, available) : 0
  # over_allocated: physical && availability.committed > availability.owned
  # move_from: the Card of the :deck printing with the most copies other than this one; ties → first
  #            in printing order; nil when there is none
  # can_add_to_collection: physical && !over_allocated && quantity > owned_copies && available <= owned_copies
  #   (exactly when CollectionCopyAdder accepts: the new copy is free for this deck iff committed <= owned,
  #   which beside "no free copy" means committed == owned)
  State = Struct.new(:key, :name, :card_type, :subtype, :display_card, :printings, keyword_init: true)
  #   #in_deck (printings with group :deck), #quantity, #owned_copies, #proxies (sums over in_deck),
  #   #over_allocated?, #single? (in_deck.size == 1), #reprinted? (printings.size > 1 — on a
  #   deck_only state that means "several printings in the deck"), #as_json (shape below)
  #   display_card: in-deck printing with the most copies, ties → first in printing order
  def self.call(user:, deck:)            # → Hash{ key => State }, one per fingerprint with ≥1 in-deck printing
  # deck.deck_cards (with card) is read as loaded. Queries: one for every printing of the deck's
  # fingerprints (Cards::Printings' order: card_sets.release_date DESC NULLS LAST, set_name, set_number),
  # then Allocations::Availability.for_cards over all of them, excluding_deck: deck — for every deck,
  # physical or not (the :owned group needs `owned`). printings order: :deck, :owned, :other, each in
  # that catalogue order.
  def self.deck_only(deck_cards)         # → Hash{ key => State }; no query, no collection data;
  # printings are the in-deck ones only, ordered by set_name then Decks::SetGroups.number_key;
  # owned/available/max_owned 0, over_allocated false, move_from nil, can_add false.

Decks::Layout.call(states:, group:)      # states: Hash or Array of State; group :type | :set → Array<Section>
  Section = Struct.new(:key, :parent_key, :kind, :label, :rows, keyword_init: true)
  #   kind :type (Pokémon, Energy), :group (Trainer container: rows [], no counts), :subtype, :set
  #   #total (rows' quantity sum), #unique (rows.size), #noun ("card"/"cards" from total; set only)
  Row = Struct.new(:key, :state, :printing, keyword_init: true)   # #quantity
  # :type → row key = state.key, printing nil; sections in page order: "pokemon", "trainer" (group),
  #   "trainer-supporter", "trainer-item", "trainer-tool", "trainer-stadium", "trainer-other", "energy"
  #   (only non-empty ones; a group is followed by its children); subtype label via
  #   Decks::ShowView::TRAINER_SUBTYPE_LABELS (move the constant to Decks::Layout and alias it on
  #   ShowView); rows sorted by [state.name, key].
  # :set → Decks::SetGroups over the :deck printings' deck_cards (card_set preloaded by the caller);
  #   row key "printing:<card_id>", printing = that PrintingState; section key "set-<card_set.id>"
  #   for a linked set, "set-code-<code.parameterize>" for an unlinked one; label = SetGroups' label.
```

### API (lane B)

Routes, inside the existing `resources :cards, controller: "deck_cards"`:
`member { post :move; post :collection_copy }` → `POST /api/decks/:deck_id/cards/:id/move`
(body `{ move: { from_card_id } }`) and `POST /api/decks/:deck_id/cards/:id/collection_copy`.

Every write — `create`, `update` (both branches), `destroy` (now 200 + payload), `move`,
`collection_copy`, `deck_card_printings#update` — answers `fingerprint_payload(card)` merged into
what it answers today (the written row's `deck_card_json` keys when the row remains;
`removed: true` when quantity 0 removed it). `group` is read from `params[:group]` (`"set"` → :set,
anything else :type). Errors: ArgumentError / NotPhysicalError → 422 `{ errors: [msg] }`.

```json
{
  "fingerprint_key": "…",
  "fingerprint": { "key", "name", "quantity", "owned_copies", "proxies",
    "printings": [ { "card_id", "set_name", "set_number", "group": "deck|owned|other",
      "quantity", "owned_copies", "proxies", "owned", "available", "max_owned",
      "over_allocated", "move_from_card_id", "can_add_to_collection" } ] } | null,
  "rows": [ { "key", "section", "html" } ],
  "sections": [ { "key", "parent", "total", "unique", "noun", "rows": ["…"], "html": "…" } ],
  "deck": { "has_proxies": true, "total": 60 }
}
```

- `fingerprint`: null when the fingerprint left the deck.
- `rows`: the fingerprint's rows in the current grouping (type: 0 or 1; set: one per in-deck printing),
  each rendered by the same component the page uses.
- `sections`: every section of the deck after the write, in page order. `total`/`unique` null for
  a `:group`; `noun` only on `:set`. `rows` (ordered row keys) and `html` (the section's empty
  shell, rendered by `Decks::DeckSection`) only on sections holding a row of this answer, and on
  their parent (`rows: []`).

### DOM (lane B renders, lane C reads)

Owner container `.deck-show-container`: `data-controller` gains `deck-rows disclosure`, loses
`deck-totals`; actions `card-search:added->deck-rows#added deck-proxies:changed->deck-proxies#toggle`.
The deck total stat value carries `data-deck-rows-target="total"`. Sections sit in
`div.deck-sections[data-deck-rows-target="sections"]`.

Section shells (`Decks::DeckSection`, rows rendered inside its list):
- `:type` → `div.deck-section[data-section-key]` > `h2` "Pokémon (" `span[data-section-total]` " — " `span[data-section-unique]` " unique)" + `ul.deck-card-list`
- `:group` → `div.deck-section-group[data-section-key="trainer"]` > `h2` "Trainer", children sections follow the h2
- `:subtype` → `div.deck-section.deck-subsection[data-section-key]` > `h3` (same counts) + `ul.deck-card-list`
- `:set` → `div.deck-section.deck-set-section[data-section-key][data-set-code]` > `h2` "Label · " `span[data-section-total]` " " `span[data-section-noun]` + `ul.deck-card-list`
A section's row list is its direct child `ul.deck-card-list`; a group's children are its direct
child `[data-section-key]` elements.

Top-level row (type view, `Decks::FingerprintRow`): `li.deck-fingerprint[data-row-key][data-fingerprint-key]`.
Set view row (`Decks::PrintingRow`, `show_name: true`): `li.deck-printing-row[data-row-key][data-fingerprint-key]`.
Sub-rows (`Decks::PrintingRow` inside `ul.deck-printing-list`): `li.deck-printing-row`, no
`data-row-key`.

Every row has one `div.deck-card-line` (layout, `data-card-preview-url`, `data-card-preview-card-id`,
`data-action="mouseenter->card-preview#show click->card-preview#open"`). The line also carries
`.deck-card-item` iff it is exactly one in-deck printing; it then holds `span.deck-card-qty` with
that printing's count. A multi-printing summary line holds `span.deck-card-total` instead.

Write buttons: `button[data-action="deck-rows#write"]` with params `data-deck-rows-url-param`,
`-method-param`, `-body-param` (JSON), `-failure-param`, and `data-focus-key`. The steppers' bodies are
steps — `{deck_card: {quantity_delta: ±1}}`, `{deck_card: {owned_copies_delta: ±1}}` — which
`Api::DeckCardsController#update` hands to the setters' `delta:`; it still takes `quantity` and
`owned_copies` (the API's other callers, the MCP tool). Each button also carries `data-focus-key`
(`qty-minus-<id>`, `qty-plus-<id>`, `real-minus-<id>`, `real-plus-<id>`, `move-<id>`, `collect-<id>`);
`disabled` when the action is impossible (quantity `−` at 0, real `−` at 0, real `+` at
`max_owned`). Classes: quantity stepper `.deck-card-qty-controls .qty-btn`; allocation
`div.deck-card-alloc` > `.qty-btn` `span.deck-card-alloc-label` ("o real · p proxy") `.qty-btn`
[`button.deck-card-collect` "+ add to my collection and use it here"] [`span.deck-card-warning`
"⚠ over-allocated"]; ⇄ `button.deck-printing-move` with `title`/`aria-label` "Move one copy here from
SET NUM"; owned note `span.deck-printing-owned` ("N owned · M free").

Disclosures (both pages): `button[aria-expanded][aria-controls][data-action="disclosure#toggle"]`
(`.deck-printings-toggle`, `.deck-printings-others-toggle`); the controlled element is `hidden` when
collapsed. ids: `deck-printings-<key with ":" → "-">`, `deck-printings-others-<same>`.

Public: container `data-controller` gains `disclosure`; rows by `Decks::PublicFingerprintRow` with
the same classes, no `data-row-key`, no write button, no alloc, no owned note.

### JS (lane C)

- `disclosure_controller.js` — `toggle({ currentTarget })` flips `aria-expanded` and the
  `aria-controls` element's `hidden`.
- `deck_rows_controller.js` — targets `total`, `sections`.
  - `write({ params: { url, method, body, failure } })`: ignored while a write is in flight;
    `requestJson`; on data → `apply(data)`.
  - `added({ detail })` → `apply(detail)`.
  - `apply(data)`: (1) remember the `aria-controls` of every expanded disclosure inside the rows it
    will replace, and the focused element's `data-focus-key`; (2) remove each
    `[data-row-key][data-fingerprint-key="<data.fingerprint_key>"]` whose key is not in `data.rows`;
    (3) for each row: replace the element with the same `data-row-key`, or insert it into its
    section's list before the first key following it in that section's `rows` that is present,
    creating the section (and its parent) from `html` when absent, placed before the first section
    following it in `data.sections` order (same parent) that is present, else appended; (4) remove
    every `[data-section-key]` whose key is not in `data.sections`; (5) write each section's `total`,
    `unique`, `noun` into its `[data-section-total]`, `[data-section-unique]`, `[data-section-noun]`;
    (6) `total` target ← `data.deck.total`; dispatch `deck-proxies:changed` `{ hasProxies }`;
    (7) re-expand remembered disclosures present in the new rows, refocus the element with the
    remembered focus key when it exists and is enabled.
- `card_search_controller.js` — `add` POSTs to its new `url` value (server-rendered, carries
  `group`), clears the field, dispatches `card-search:added` with the answer as detail; no Turbo
  visit. `deckKey` value removed.
- Deleted: `deck_card_quantity_controller.js`, `deck_card_owned_copies_controller.js`,
  `printing_picker_controller.js`, `deck_totals_controller.js`.

## Lanes

- **A — services** (isolated worktree): `Card#fingerprint_key`, comparator read, the four services,
  `Decks::Layout` (+ constant move), MCP description, their tests. Files: `app/models/card.rb`,
  `app/services/decks/{comparator,deck_card_quantity_setter,copy_mover,collection_copy_adder,fingerprint_states,layout}.rb`,
  `app/views/components/decks/show_view.rb` (constant alias only), `app/mcp/set_deck_card_quantity_tool.rb`,
  `test/services/decks/*`, `test/models/card_test.rb`, `test/mcp/write_tools_test.rb`.
- **C — JavaScript** (this worktree, Vitest only): the JS above and its tests under
  `test/javascript/controllers/`.
- **B — views and API** (this worktree, after A merges): components, `ShowView`, `PublicShowView`,
  styleguide demo, CSS, `DecksController` (owner_show and edit build states), the API controllers,
  `DeckCardPayload`, routes, controller/component/integration tests.
- **D — system tests** (after B and C): rewrite the system tests listed in the batch recon to the new
  structure, add the motivating case end to end, both viewports.

## Tests per plan-adversary finding

Each entry names a decision the existing suite would not notice, the test that holds it, and its lane.

- A1 increase claims free copies with `excluding_deck` — collection 3, row q1/o1, set 3 → o3; a second
  physical deck backing 1 → o2. Delete `deck_card_quantity_setter_test.rb` "does not auto-bump reals".
- A2 a decrease never claims — collection 3, row q4/o1, set 3 → o1.
- A3 non-physical never claims — collection 3, row q1/o0, set 3 → o0.
- A4 a new row counts as 0 — no row, collection 2, set 3 → q3/o2; non-physical → o0.
- A5 setter inside `serialized_transaction` — the depth probe of `test/mcp/bulk_add_tools_test.rb:248`.
- A6 MCP greedy — `SetDeckCardQuantityTool` q1/o1 (collection 3) → 3 reports 3 real.
- A7 `CopyMover` refusals (same card, foreign fingerprint, blank fingerprint, absent source), source
  destroyed at 0, proxy dropped first on the source, greedy on the target, non-physical o0.
- A8 `CollectionCopyAdder` — no proxy → refused; free copy → refused, nothing written; over-allocated
  printing → refused and collection unchanged; happy path collection +1 and o+1 in one transaction.
- A9 `FingerprintStates` — tie on copies → `move_from` is the newer set; groups and order
  (:deck, :owned, :other, catalogue order); `max_owned`, `can_add_to_collection`, `over_allocated`;
  `deck_only` orders by set code then `number_key` (GG2 < GG10) and runs no query.
- A10 `Layout` — type keys/order/Tool fold/name sort; set keys `set-<id>` and `set-code-<code>`.
- B1 "unique" counts fingerprints — `budew_pre`×1 + `budew_asc`×2 + `honedge`×1 → "Pokémon (4 — 2 unique)"
  on owner and public pages.
- B2 one row per fingerprint / per printing — type view one `li.deck-fingerprint[data-fingerprint-key]`;
  set view two `li.deck-printing-row[data-row-key^="printing:"]` in PRE and ASC sections.
- B3 image-export contract — owner and public: `.deck-card-item` count 2, `.deck-card-qty` {1,2}, one
  `.deck-card-total` "3" outside every `.deck-card-item`. (C: Vitest over `buildImage`'s collection
  step on that markup → [1,2].)
- B4 single-printing expansion does not repeat itself; toggle only where a reprint exists.
- B5 public page carries none of `[data-action~="deck-rows#write"]`, `.deck-printing-owned`,
  `.deck-printing-move`, `[data-row-key]`, `.deck-card-collect`, `.deck-card-alloc`; the owner's
  request on the same deck carries each.
- B6 public order set code then number vs owner catalogue order (POR budew reprint); visitor still 7 queries.
- B7 flat cost with fingerprints holding ≥2 non-deck printings in different sets, owned and not.
- B8 payload — `group=set` row keys/sections; type row key = fingerprint key; merging swap lists both
  printings; DELETE answers 200 with `removed`, `fingerprint: null`, `rows: []` and the section gone;
  DELETE one of two → remaining quantity.
- B9 set-section spans `[data-section-total]`, `[data-section-noun]`, keys `set-<id>`, `set-code-pal`.
- C1 `card_search#add` → POST to `url` value, `card-search:added` with the reply, field cleared, no
  `Turbo.visit`; fixture drops `deck-key`.
