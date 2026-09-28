# Deck versions — implementation plan

Spec: `docs/superpowers/specs/2026-09-28-deck-versions-design.md`. Two lanes, disjoint files,
against the frozen contract below.

## Frozen contract

### Schema (migration `CreateDeckVersions`)

```
deck_versions:       deck_id NOT NULL FK, effective_at datetime NOT NULL, format string NOT NULL,
                     standard_pool_id FK NULL, other_format_name string NULL, timestamps
                     index (deck_id, effective_at)
deck_version_cards:  deck_version_id NOT NULL FK, card_id NOT NULL FK, quantity integer NOT NULL,
                     timestamps; UNIQUE (deck_version_id, card_id); CHECK quantity > 0
deck_results.deck_version_id        FK, NOT NULL after backfill, indexed
tournament_entries.deck_version_id  FK, NOT NULL after backfill, indexed
```

Backfill in the migration, plain SQL, for every deck with ≥1 result or ≥1 entry (25 on the prod
copy): one version, `effective_at = MAX(decks.created_at, MAX(deck_cards.updated_at))`, the deck's
current format / pool / other_format_name, one `deck_version_cards` row per `deck_cards` row with
`quantity > 0`; then point every result and entry of that deck at it; then `change_column_null`.
Verified by counts against the development database (a prod copy), since CI loads the schema and
never runs a migration.

### Models

- `DeckVersion` — `belongs_to :deck`, `belongs_to :standard_pool, optional: true`,
  `has_many :deck_version_cards, dependent: :destroy`, `has_many :deck_results,
  dependent: :restrict_with_error`, `has_many :tournament_entries, dependent: :restrict_with_error`.
  - scope `ordered` → `order(:effective_at, :id)`.
  - `attr_writer :number`; `#number` returns the written value, else computes the rank by
    `(effective_at, id)` within the deck with one COUNT.
  - `#label` → `"v#{number}"`; `#name` → `label` (what `Decks::Comparator` callers print).
  - `#deck_cards` → `deck_version_cards` (duck type read by `Decks::Comparator`).
  - `#format_label` → `"Standard TEF-PBL"` / `"Expanded"` / other_format_name — same wording the
    deck page already uses for its format badge (reuse whatever helper that is).
  - validations: `effective_at` present and not in the future; `format` in `Deck::FORMATS`
    (whatever the constant is named); pool required iff standard, `other_format_name` iff other —
    same rules as `Deck`.
- `DeckVersionCard` — `belongs_to :deck_version`, `belongs_to :card`, `quantity` integer > 0.
- `Deck` — `has_many :deck_versions, -> { ordered }, dependent: :destroy`, declared **after**
  `:deck_results` and `:tournament_entries` (results must go before their version).
  - `#latest_version` → last of `deck_versions` by `(effective_at, id)`.
  - `#ordered_versions` → array of versions with `number` written 1..n (one query).
- `DeckResult` — `belongs_to :deck_version`. `before_validation`: when `tournament_entry` is
  present, `self.deck_version = tournament_entry.deck_version`. Validations: version's `deck_id`
  equals `deck_id`; with an entry, version equals the entry's.
- `TournamentEntry` — `belongs_to :deck_version`. Validation: version's `deck_id` equals `deck_id`.
  `after_update` when `deck_version_id` changed: `deck_results.update_all(deck_version_id:)`
  (inside the save transaction).

### Services (`app/services/decks/`)

- `Decks::VersionDrift.call(deck)` → `Result(drift?, latest)`. `drift?` is false when there is no
  version. Compares `{fingerprint-or-"card:<id>" => summed quantity}` of live `deck_cards` against
  the latest version's cards, plus `format`, `standard_pool_id`, `other_format_name`. Two queries
  max, no per-card query.
- `Decks::VersionSnapshot.call(deck, effective_at: Time.current)` → the created `DeckVersion`
  (raises on invalid). Copies live rows with quantity > 0.
- `Decks::VersionImporter.call(deck:, decklist:, effective_at:, format:, standard_pool:,
  other_format_name:)` → `Result(version, errors)`. Parses lines with `Decks::Fetcher::CARD_LINE_RE`
  (sum repeats), resolves through `Cards::ReferenceResolver` (never fetches). No parsable line →
  error; any unresolved reference → error naming it, nothing written. Unparsable non-blank lines
  are reported as errors too (not dropped silently — the `Decks::Fetcher` trap).
- `Decks::VersionResolver.call(deck:, choice:, tournament_entry: nil)` → a `DeckVersion`, or raises
  `Decks::VersionResolver::ChoiceRequired` (attrs `current_number`, `next_number`). Order:
  1. entry given → `entry.deck_version` (choice ignored);
  2. no version → snapshot (choice ignored);
  3. no drift → latest;
  4. `"new"` → snapshot; `"current"` → latest;
  5. otherwise raise.
  Callers wrap resolve + save in one `serialized_transaction`, so a snapshot never survives a
  result that failed validation.

### Controllers and routes

- `Api::DeckResultsController#create` — reads top-level `version_choice`. On `ChoiceRequired`:
  **409** `{ error: "version_choice_required", current_version: N, next_version: N+1 }`, nothing
  written. Success JSON gains `deck_version: { number:, id: }`.
- `Tournaments::EntriesController#create` — top-level `version_choice`; on `ChoiceRequired` sets
  `@version_prompt = { current: N, next: N+1 }` and renders `:new` 422. `#update` permits
  `deck_version_id`; when `deck_id` changes, resolves again with `version_choice` (same prompt,
  renders `:edit`). `#attach_results` also writes `deck_version_id: @entry.deck_version_id`.
  `set_form_collections` also loads the edited entry's deck versions for the select.
- `DeckResultsController#update` permits `deck_version_id` (overridden by the model when an entry
  is attached).
- `DeckVersionsController` nested `resources :versions, controller: "deck_versions",
  only: %i[index show new create edit update destroy]` with `post :snapshot, on: :collection`,
  under `resources :decks`. Lookup `current_user.decks.find_by!(key:)`, `authorize @deck, :stats?`,
  versions via `@deck.deck_versions.find`. Rides out of `authenticate :user` like `deck_results`,
  so `authenticate_user!` stays its gate; add a case per action to
  `test/controllers/public_access_test.rb`.
  - `index` — `@versions = @deck.ordered_versions`, `@drift = Decks::VersionDrift.call(@deck)`.
  - `show` — diff with the previous version: `@comparison = Decks::Comparator.call([prev, v])`
    (`[v]` alone for v1).
  - `snapshot` — refused (redirect + alert) when a version exists and there is no drift.
  - `new`/`create` — the earlier-version import form (textarea, datetime, format fields).
  - `edit`/`update` — `effective_at` only.
  - `destroy` — branches on `destroy`'s return, names the count in the alert.
- `DecksController#stats` — `@versions = @deck.ordered_versions`; `?version=N` (the number)
  scopes `@results`; unknown N → all. Results preload `:deck_version`.

## Lane 1 — server

Files: migration, `db/schema.rb`, the three models above + `DeckVersion`/`DeckVersionCard`, the
four services, the five controllers, `config/routes.rb`, fixtures (`deck_versions.yml`,
`deck_version_cards.yml`, `deck_version_id` on every `deck_results.yml` / `tournament_entries.yml`
row), and tests under `test/models`, `test/services/decks`, `test/controllers`.

## Lane 2 — views

Files: `app/views/components/deck_versions/*` (index, show, new, edit), `Decks::StatsView` +
a `Decks::VersionSummaryTable`, `Decks::ResultModal` (prompt panel), `result_modal_controller.js`,
`helpers/api.js` (option to hand a 409 body back instead of flashing it),
`Tournaments::Entries::Form` (prompt radios + version select on edit), `DeckResults::EditView`
(version select, disabled with a hint when an entry is attached), `Decks::ActionsDropdown`
("Versions" link, owner only), `app/views/deck_versions/*.html.erb` shells, CSS, and system tests.
May parameterise `Decks::CompareView`'s header link for reuse on `show`.

## Contract corrections (plan adversary, 2026-09-28) — these override the text above

1. Formats: `Deck.formats` (enum, `validate: true`) and `Deck::FORMAT_LABELS`. `DeckVersion`
   declares the same enum and `#format_label` with `Deck#format_label`'s exact wording
   (`"Standard (TEF-PBL)"`, `"Other"` when the custom name is blank) — extract the shared body into
   a concern `FormatLabelled` used by both, rather than two copies.
2. Transactions: `serialized_transaction` is a private instance method of `ApplicationService`.
   So the write paths go through **services**: `Decks::ResultRecorder.call(deck:, attributes:,
   choice:)` → `Result(result, errors)` or raises `ChoiceRequired`; entries use
   `Decks::VersionResolver` inside `TournamentEntry.transaction` with `save!` rescued. **Every
   version-creating write uses `save!`** (a false `save` does not roll back — verified), so a
   snapshot never survives an invalid result or entry.
3. 409 body is `{ error: "version_choice_required", current_version: N, next_version: N+1 }`
   (the spec's `drift: true` wording is replaced by this one).
4. `TournamentEntry` cascade uses `after_update` + `saved_change_to_deck_version_id?`
   (`deck_version_id_changed?` is false there — verified).
5. **No model fallback.** `DeckResult`/`TournamentEntry` without a version are invalid ("Deck
   version must exist"); the only automatic assignment is result ← entry's version. Every test
   construction site gets an explicit version; add a test helper
   `deck_version_for(deck)` (returns latest or snapshots) in `test/test_helper.rb` for brevity.
   `tournament_entry_test.rb:120`-style deck changes must pass a version of the new deck.
6. Backfill: `effective_at = COALESCE(MAX(deck_cards.updated_at), decks.created_at)` compared
   with `decks.created_at` via `MAX` **after** the COALESCE (SQLite `MAX(x, NULL)` is NULL —
   verified). Backfill SQL lives in public instance methods of the migration class, tested the way
   `archetype_test.rb:169` tests `AddFingerprintsToArchetypes`: a deck with results and no cards,
   a deck with only an entry, a deck with neither.
7. `Decks::Comparator` keys rows on `card.fingerprint || "card:#{card.id}"` — today every
   nil-fingerprint card collapses into one row, which would make the diff disagree with drift.
   `Decks::CompareView`'s header link becomes a parameter (lane 2).
8. Importer accepts blank lines and the PTCG section headers (`/\A(Pokémon|Trainer|Energy|Total
   Cards):\s*\d+\z/`); every other non-card line is refused by name.
9. Version selects (result edit, entry edit) render from `@deck.ordered_versions` — flat cost.
10. `DeckVersionsController` gets `after_action :verify_authorized`.

## Tests — the "would stay green" list, each assigned

Lane 1 (server):
- API 409: drifted deck with v1, no choice → 409 with both numbers, no row written (results,
  versions, version cards); `current` → v1; `new` → v2 and JSON number 2; `new` on a non-drifted
  deck → no new version.
- API invalid result (`match_format: "bo5"`) on a deck with no version, and on a drifted deck with
  `new` → 422 and version count unchanged.
- Entry inheritance: result built with entry (v1) and `deck_version: v2` saves on v1; API POST with
  `tournament_entry_id` on a drifted deck and no choice → 201 on the entry's version.
- `attach_results` onto an entry on v1 of a result on v2 → result on v1.
- Entry version move cascades to its 2 results; an invalid entry update with a version change
  leaves results unchanged.
- No fallback: result / entry without version invalid.
- Cross-deck: PATCH result with another deck's version → 422, unchanged; PATCH version on an
  entry-attached result → stays on entry's version.
- Entry create prompt: drifted deck, no choice → 422, radios v1/v2 in body, counts unchanged;
  `new` → entry on v2; stranger's deck → no version created, no prompt.
- Stats: v1 win "A", v2 loss "B"; `?version=1`, `?version=2`, `?version=99`; summary 1-0 / 0-1;
  flat query count at 1 and 3 versions.
- Numbering: an earlier import renumbers (both `#number` and `ordered_versions`); equal
  `effective_at` ordered by id; another deck's earlier version does not shift numbers.
- Flat cost of result edit and entry edit at 1 vs 4 versions.
- Drift: printing swap none; 2+2 split vs 4 none; nil-fingerprint swap drift; pool change drift;
  `other_format_name` change drift; `owned_copies` change none; ≤ 2 queries at 1 and 10 cards.
- Comparator: nil-fingerprint swap yields a differing row.
- Snapshot action refused without drift; with drift, cards equal live; destroy restricted naming
  "1 result" / "1 participation"; empty version destroyed with its cards; future `effective_at` 422.
- Owner only: stranger 404 on every action; public_access_test rows; visitor sees no versions link
  (extend `decks_controller_test.rb:1317`).
- Migration backfill (three shapes above).
- Importer: section headers accepted; `4 Honedge POR` refused by name; `POR 999` refused, nothing
  written.
- Duplicator: copy has no versions.

Lane 2 (views, system tests, both viewports):
- Modal: deck with v1 plus an added card → Log Result → prompt offers "Create version 2" /
  "Attach to version 1" / "Cancel"; each path's effect; Cancel writes nothing and Save is enabled
  again.
- Import an earlier version then move a result onto it via the edit form; stats table shows both.
- Versions show page header links are not `/decks/<id>`, and a changed row is marked.
