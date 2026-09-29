# Deck versions

A physical deck is edited in place — that is what happens to the cards on the table — while its
results keep accumulating. `DeckVersion` is what lets a result say which list, format and
Standard pool it was played with. Spec: `docs/superpowers/specs/2026-09-28-deck-versions-design.md`;
the review decisions that reshaped it are in the plan's "Round 2" section.

The case that motivated it, measured on a production copy: deck 1281 carried one match on
2026-09-17 and four on 2026-09-22 under list A, the list was edited on 2026-09-23 at 16:40
(`MAX(deck_cards.updated_at)`), and four more matches followed under list B — all nine filed
against "the deck". List A existed nowhere in the database.

## The model

- **A version is an immutable snapshot**: `deck_version_cards` (printing + quantity) plus
  `format`, `standard_pool_id`, `other_format_name` and `effective_at`. The live deck may diverge
  from its latest version; editing the deck never touches a version. `owned_copies` is not
  snapshotted — allocation is present-state inventory, not a property of the list played.
- **`deck_results.deck_version_id` and `tournament_entries.deck_version_id` are `NOT NULL`.** There
  is no model fallback: a result without a version is invalid. The single automatic assignment is
  result ← its participation's version (`DeckResult#inherit_entry_version`), and only for a
  participation of the same deck. Moving a participation to another version moves its results in
  the same save (`after_update` on `saved_change_to_deck_version_id?` — `deck_version_id_changed?`
  is already false there).
- **Numbers are derived, never stored**: a version's number is its rank by `(effective_at, id)`
  within its deck. `effective_at` exists to order versions and nothing else — it is **never printed
  as a validity period**, because it is either an estimate (the backfill) or the moment a button was
  clicked. What a page prints is `Decks::VersionPeriods`: the span of the version's results'
  `played_at` and its participations' tournament dates, read in the app's zone (a 00:30 Paris
  match read as UTC lands on the day before). On the production copy the backfill files 36 of 123
  results on a version whose `effective_at` is later than the match — harmless only because of
  this rule.
  Two consequences of reading matches rather than a date: results whose `played_at` was cleared
  (the edit form accepts it) are counted and printed as "1 match · date unknown", never as "not
  played yet"; and a participation at an event still to come neither dates nor counts, since
  `Tournament` accepts a future date and an event not yet held is not a time the list was played.
- **A date is corrected, never used to reorder.** Editing `effective_at` must keep the version
  strictly between its neighbours (`DeckVersion#effective_at_stays_between_neighbours`): moving
  past one would bypass both of the import's rules below at once — an old list becoming the one
  drift is measured against, or two identical lists landing side by side. Strict, because at a
  neighbour's exact instant the id decides the rank, which is a reorder too.
- **Drift** (`Decks::VersionDrift`) compares the live deck with its latest version by
  `COALESCE(NULLIF(fingerprint, ''), 'card:' || id)` and summed quantity, plus the three
  classification columns — so a printing swap or a proxy turned real is not drift, and a pool
  change alone is. `Decks::Comparator` keys its rows the same way; before this feature it folded
  every fingerprint-less card into one row, and the diff page would have contradicted the drift that
  sent the reader to it. `Result#message(number)` is the **only** place the sentence is composed
  ("The Standard pool has changed since version 2 (TEF-PBL → TEF-30C)."); the modal, the entry form
  and the versions page print it.

## Writing a result or a participation

`Decks::VersionResolver` decides: a participation's version wins; a deck with no version gets v1
silently; an undrifted deck answers its latest; a drifted one needs `version_choice` = `new` |
`current`, and otherwise raises `ChoiceRequired`. `Api::DeckResultsController#create` answers that
with a **409** (`error`, `current_version`, `next_version`, `message`) and writes nothing; the modal
asks and resubmits with the fields **as they stand at the click** (only `played_at` is kept from the
first Save — resending the frozen payload filed a "win" the reader had corrected to a loss).
`Tournaments::EntriesController` re-renders the form with radios instead.

**Resolve and save run in one transaction, and the save is `save!`.** A `save` that returns false
does not roll a transaction back, so a snapshot taken for a result that then fails validation
would survive it. `Decks::ResultRecorder` exists for exactly that, inside `serialized_transaction`.

## Reconstructing the past

"Add an earlier version" (`Decks::VersionImporter`) takes a pasted list, resolves printings through
`Cards::ReferenceResolver` (never fetches), and refuses — writing nothing — an unreadable line (PTCG
section headers and blank lines are skipped), an unknown printing, a quantity outside 1..60, a
date not strictly before the latest version (the present is "New version"'s job), and a list
identical to the version just before or just after it (a re-import used to duplicate and renumber
every later version; a list identical to a *distant* version stays legal — A → B → A is real play).
The form defaults its format and pool to the **oldest** version's, the one the import will sit
before: after a rotation the deck's own pool is the wrong default for its past.

## Deletion

A version with a result or a participation refuses to be destroyed. `Deck has_many
:deck_versions` is declared after `:deck_results`, so a deck's results go before their versions.
`Card` and `StandardPool` both `restrict_with_error` on versions: a recorded list must not lose a
line, or its pool, as a side effect of an admin delete. Tests that need a printing gone use
`remove_printing` (test_helper), which clears the fixture version rows first and `destroy!`s.

## The backfill

`CreateDeckVersions#backfill` is public and tested directly (CI loads the schema and never runs a
migration): every deck with a result or an entry gets v1 = its current list, dated
`MAX(COALESCE(MAX(deck_cards.updated_at), decks.created_at), decks.created_at)` — COALESCE first,
since SQLite's two-argument `MAX` is NULL as soon as either side is. Measured on the production
copy: 25 versions, 638 version cards, 0 results and 0 entries left without a version, deck 1281's
v1 at 2026-09-23 16:40:50 holding its 60 cards.

## Surface

Owner only: `DeckVersionsController` sits under `resources :decks` (so outside
`authenticate :user` by nesting, like `deck_results`), keeps `authenticate_user!`, looks the deck up
through `current_user.decks`, `authorize`s with `DeckPolicy#stats?` and carries
`verify_authorized`. Nothing about versions is public; a shared deck's page is unchanged.
