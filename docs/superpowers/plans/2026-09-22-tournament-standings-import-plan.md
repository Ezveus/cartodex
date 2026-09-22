# Plan — import one whole tournament from Limitless

Design record: `docs/superpowers/specs/2026-09-22-tournament-standings-import-design.md`.
Baseline before any change: **1988 runs, 9371 assertions, 0 failures** (unit suite, in
`cartodex-test:4.0.6`; the host cannot run it — no libvips).

---

## 0. The frozen contract

Every lane codes against these names. No lane renegotiates one.

### New model

```ruby
# app/models/limitless_archetype_mapping.rb
class LimitlessArchetypeMapping < ApplicationRecord
  belongs_to :archetype
  # limitless_deck_id :integer  NOT NULL
  # limitless_variant :integer  NULL  — the ?variant=N of the href, nil for the base deck
  # label             :string   NOT NULL — display name as last seen, never a key
  # archetype_id      :integer  NOT NULL

  def self.reference(deck_id, variant) = variant ? "#{deck_id}/#{variant}" : deck_id.to_s
  def self.by_reference          # => { "284/3" => mapping }
  def reference
end
```

Indexes — **two partial ones, the `index_tournament_entries_on_tournament_and_profile` split**:
`(limitless_deck_id, limitless_variant)` UNIQUE `WHERE limitless_variant IS NOT NULL`, and
`limitless_deck_id` UNIQUE `WHERE limitless_variant IS NULL`. SQLite treats NULLs as distinct, so a
plain composite index alone lets one base deck take a mapping row per confirmation — **verified
against the image's SQLite: two `(284, NULL)` rows are accepted under a plain composite UNIQUE
index, two `(284, 3)` rows are not.** Both halves therefore need their own test, spelled
`assert_raises(ActiveRecord::RecordNotUnique)` — a bare `assert_raises` is satisfied by the Ruby
validation and proves nothing about the database.

`Archetype has_many :limitless_archetype_mappings, dependent: :destroy` — **not** optional
bookkeeping. With a bare FK, destroying an archetype a mapping points at raises
`ActiveRecord::InvalidForeignKey`, and `Admin::ArchetypesController#destroy` has no rescue: an
unrescued 500. `:destroy` rather than `:restrict_with_error` because a mapping is a machine's note
about how to read a source, and once its archetype is gone the answer it holds is unwritable
(`archetype_id` is `NOT NULL`) — destroyed, the next import simply asks again.

### New parsers — two of them, six requests for a whole event

```ruby
Tournaments::LimitlessEventResults.call(tournament_id) # => [Row, …]
Tournaments::LimitlessEventResults::Row = Struct.new(
  :event_name, :event_date, :division, :division_suffix, :format,
  :player_name, :placement, :list_url,
  :archetype_key, :archetype_label, :attendance,
  keyword_init: true
)
Tournaments::LimitlessEventResults::ParseError < StandardError
Tournaments::LimitlessEventResults::DIVISION_PAGES = { "masters" => nil, "senior" => "SR", "junior" => "JR" }
```

- `archetype_key` is `"284"` or `"284/3"`, from the deck cell's `href="/decks/<id>(?variant=<n>)"`.
- `attendance` is the **division's** field size off that page's `infobox-line`, nil for `? Players`.
- `format` is the pool code as published, `"TEF-PBL"` — **not** a Limitless format label.
- `list_url` is **not** an HTTP URL here but the synthetic key `"<id>/<division>/<rank>"`, which is
  what the bulk decklist store below answers on. It stays in that field so the importer's existing
  `row.list_url.blank?` gate keeps working unchanged.
- **The base page and a division page fail differently, and the plan used to say both.** The base
  page (`/tournaments/<id>`) holding no table raises `ParseError` naming the URL — the event does
  not exist, or the layout moved. A **suffix** page (`/SR`, `/JR`) that 404s or holds no table is an
  empty division and is skipped: 563's SR and JR pages answer 200 with `? Players` and no table, so
  making them fatal would put every small event permanently out of reach.

```ruby
Tournaments::EventDecklists.new(tournament_id)   # fetches lazily, once per division page
#   .call(list_url)    -> PTCG text, or raises — the `decklist_service:` interface, unchanged
```

It reads `/tournaments/<id>[/<SUFFIX>]/decklists` and keys each block on its `data-target`
(`decklist-<rank>`), the `data-rank` of the results page. **Measured on 577**: 22.1 MB, 559 blocks,
`Nokogiri::HTML` 0.30 s, walking all of them 0.28 s, RSS 50 → 246 MB. This is what makes the whole
feature six requests instead of 575 (12.7 min measured), and what makes the preview's proposal cost
one request instead of 45 (37 s measured).

**`Tournaments::LimitlessDecklist` gains a class method and keeps one spelling of its rule:**

```ruby
Tournaments::LimitlessDecklist.from_nodes(card_nodes, source:) # => PTCG text
```

`#call` becomes that method applied to `doc.css("[data-text-decklist] .decklist-card")`, and
`EventDecklists` calls it per block. `source:` replaces `@url` in every error message. Copying the
rule instead is the failure `Decks::Fetcher::SET_CODE_RE` exists to prevent.

### New resolver

```ruby
Tournaments::ArchetypeProposer.call(list_text:, label:, archetypes:)
# => Proposal(archetype:, verdict:, candidates:)
#    verdict ∈ :decided | :name_says_nothing | :ambiguous | :no_candidate
```

`Decks::ArchetypeDetector` grows a **public class method** and the proposer calls it:

```ruby
Decks::ArchetypeDetector.candidates(fingerprints, archetypes: Archetype.all) # => [[archetype, score], …]
```

`#match_existing` becomes `candidates(deck_fingerprints).max_by { … }` and nothing else moves.
Re-implementing containment in the proposer is refused: it has four clauses that can each be got
subtly wrong (the `joins(:primary_card)` restriction, the `points.positive?` filter, the
`return 0 unless members.all?` disqualification, and keying on `Card#fingerprint` rather than on
name), and a copy that diverged on any of them would still satisfy a test written against one of
them. One spelling, the `Decks::Fetcher::SET_CODE_RE` rule.

The proposer therefore resolves the list text to fingerprints itself — that part the detector does
not do — and only the **ranking** is its own: `[-name_overlap, -score, name]`, with `:decided`
requiring a strict lead on the first two. `archetype` is nil for every verdict but `:decided`.
**A single candidate with zero overlap is `:name_says_nothing`, not `:decided`** — that is 9 of the
96 measured rows (`Basic Box`, `Tera Box`), and it is the shape a `return :decided if
candidates.one?` short-circuit would get wrong while passing every other case.

**The tokenisation is the measured one and must be reproduced exactly**, or the numbers in the spec
stop being about this code:

```ruby
STOP_WORDS = %w[mega ex box the and].freeze
def tokens(name)
  name.downcase.gsub(/[^a-z0-9 ]/, " ").split
      .reject { |t| t.length < 3 || STOP_WORDS.include?(t) }.to_set
end
overlap = tokens(limitless_label) & tokens(archetype.name)
```

`mega` and `ex` are dropped because cartodex spells an archetype `Mega Lucario ex / Hariyama` where
Limitless spells the same deck `Lucario Hariyama` — kept, they inflate every Mega archetype's
overlap by one against every Mega deck name and the discriminator stops discriminating. `box` is
dropped because `Basic Box`, `Tera Box` and `Toxtricity Box` are Limitless's word for "no single
deck name fits", which is precisely the case that must come out `:name_says_nothing`. Tokens under
three characters go because `N's Zoroark` tokenises to `zoroark` either way and a bare `n` would
match any archetype whose name contains a three-letter word starting with n.

`score` is `Decks::ArchetypeDetector`'s weights, reused and **not re-spelled**: rule-box Pokémon 3,
other Pokémon 2, anything else 1. Extract them from that service rather than copying the numbers.

Reference verdicts, **measured 2026-09-22 against the development catalogue of 81 archetypes and
real lists off event 577**. They are the record of why the rule is shaped this way; they are *not*
fixture expectations, because `test/fixtures/archetypes.yml` holds a different catalogue. A test
reproducing one of these builds the archetypes and the list it needs and says which case it is
standing in for.

| label | verdict | archetype |
|---|---|---|
| `Slowking` | `:decided` | Slowking — **not** Lillie's Clefairy ex |
| `N's Zoroark` | `:decided` | N's Zoroark ex |
| `Grimmsnarl Froslass` | `:decided` | Marnie's Grimmsnarl ex / Froslass |
| `Dhelmise` | `:ambiguous` | nil (Banette and Sinistcha tie at overlap 1, score 4) |
| `Basic Box` | `:name_says_nothing` | nil |
| `Marnie's Grimmsnarl` | `:no_candidate` | nil |

### Changed contracts (shared by all three sources)

| Where | Was | Becomes |
|---|---|---|
| `StandingsImportPlan::EventPlan#participant_count` | one Integer | `#participant_counts`, a Hash `{division => count}`; the online source supplies `{"open" => n}` |
| `StandingsImportPlan::RowPlan` | no archetype | gains `archetype` (an `Archetype` or nil) |
| `StandingsImportPlan#standard_pool_for` | `return @standard_pool if @online` | `return @standard_pool if @standard_pool` |
| `StandingsImporter#initialize` | `archetype:` required | `archetype: nil`; a standing is written with `row_plan.archetype || @archetype`, and a row with neither is planned `:blocked` |
| `StandingsImportPlan::DEFAULT_MAX_ROWS` | 300 | unchanged; the new source passes `max_rows: 1000` |

This source is **not** online: `online: false`, so it is catalogued and partitions with the paper
half. It sets **no** `event_key`, so `find_catalogued` uses `(name_normalized, date)` — which is the
decision, and also avoids the trap that looking up by a key the existing row does not carry would
plan a create that the `(name, date)` UNIQUE index then refuses.

---

## 1. Lanes

Lanes are disjoint by file but **run one after another, not in parallel**, and that is a decision
rather than a shortage of nerve. The test database is one shared SQLite file with no
`TEST_ENV_NUMBER`, so two agents running `bin/rails test` at once collide on loading fixtures —
which leaves two options, and the obvious one is worse. Write-only lanes could run in parallel, but
a lane that cannot run its tests cannot do TDD: it never sees red, and "the test I wrote would have
failed" is exactly the claim this pipeline exists to stop anyone making. So each lane runs
sequentially, in this worktree, with the container and the suite to itself.

Every lane runs the suite as:

```
docker run --rm -v "$PWD":/app -v cartodex-bundle:/bundle -w /app -e RAILS_ENV=test \
  cartodex-test:4.0.6 bash -lc 'bin/rails db:test:prepare test <FILE>'
```

The host cannot run it — no libvips.

### Lane A — the source and the resolver

| File | |
|---|---|
| `app/services/tournaments/limitless_event_results.rb` | new |
| `app/services/tournaments/event_decklists.rb` | new |
| `app/services/tournaments/limitless_decklist.rb` | extract `.from_nodes` |
| `app/services/tournaments/archetype_proposer.rb` | new |
| `test/services/tournaments/limitless_event_results_test.rb` | new |
| `test/services/tournaments/event_decklists_test.rb` | new |
| `test/services/tournaments/limitless_decklist_test.rb` | extended |
| `test/services/tournaments/archetype_proposer_test.rb` | new |
| `test/fixtures/files/limitless/tournament_577*.html` | new, trimmed captures |

### Lane B — the mapping store and the plan/importer contract

| File | |
|---|---|
| `db/migrate/*_create_limitless_archetype_mappings.rb`, `db/schema.rb` | new |
| `app/models/limitless_archetype_mapping.rb` | new |
| `test/fixtures/limitless_archetype_mappings.yml` | new |
| `app/services/tournaments/standings_import_plan.rb` | `participant_counts`, `RowPlan#archetype`, pool override, mapping resolution |
| `app/services/tournaments/standings_importer.rb` | optional `archetype:`, per-row archetype, per-division counts |
| `test/models/limitless_archetype_mapping_test.rb` | new |
| `test/services/tournaments/standings_import_plan_test.rb`, `…/standings_importer_test.rb` | extended |

### Lane C — the screen

| File | |
|---|---|
| `app/controllers/admin/standings_imports_controller.rb` | third source, mapping params |
| `app/jobs/tournaments/limitless_import_job.rb` | third source |
| `config/routes.rb` | if a mapping route is needed |
| `app/views/components/admin/standings_imports/*.rb` | form, mapping table, plan table |
| `test/controllers/admin/standings_imports_controller_test.rb`, `test/jobs/…` | extended |
| `test/system/tournament_event_import_test.rb` | new |

Lane C consumes A's and B's names and must not edit their files. It starts once the contract above
is in the branch as stubs (I write the stubs before dispatching).

---

## 2. What the tests must pin

Written before the code, one per claim, each sabotage-verified afterwards.

**The parser (A)**

1. The three division pages become one event: one name, one date, rows carrying `masters`,
   `senior`, `junior`.
2. The division's own attendance is read per page — 3122 / 364 / 233, not one number three times.
3. `? Players` yields nil, not 0. *(This is the test a fixture built only from 577 cannot have; the
   Cape Town capture is why a second fixture exists.)*
4. `archetype_key` distinguishes `284` from `284/3` — a base deck and its variant are two keys.
5. The format is the pool code as published, `"TEF-PBL"`.
6. A row whose deck cell carries no href yields a nil `archetype_key` and is not dropped.
7. **Two tests, stubbed per URL, because one rule does not cover both pages.** (a) the base page
   table-less, the suffix pages fine → `assert_raises(ParseError)` whose message names
   `/tournaments/577`; (b) the base page fine, the SR page 404 or table-less → the call returns
   `masters` and `junior` rows and **does not raise**. A single test stubbing all three passes
   under either rule and pins nothing.

**The bulk decklist store (A)**

7a. One fetch answers every row of a division — assert the fetch count, not just the texts, or the
    whole point of the service is unpinned.
7b. A rank with no block answers nil rather than raising, and the row becomes a standing with no
    field list. *(Cape Town: 10 rows, 6 lists.)*
7c. A division page is fetched only when a row of that division asks for it.
7d. `LimitlessDecklist.from_nodes` and `LimitlessDecklist.call` produce byte-identical text for the
    same markup, and both refuse the same bad printing with the same message shape — the two paths
    are one rule.

**The resolver (A)**

8. `Slowking` resolves to `Slowking` and not to `Lillie's Clefairy ex` — the measured regression.
9. Two candidates tied on overlap *and* score yield `:ambiguous` with `archetype` nil, never a
   winner. *(Dhelmise between Banette and Sinistcha.)*
10. Zero overlap yields `:name_says_nothing`, **in two separate cases**: with two candidates, and
    with exactly **one**. The one-candidate case is what a `return :decided if candidates.one?`
    short-circuit gets wrong while passing everything else, and it is 9 of the 96 measured rows.
11. Containment finding nothing yields `:no_candidate`.
12. **A differential test, not a clause test**: build a `Deck` from the same list text and assert the
    proposer's candidate set equals the set `Decks::ArchetypeDetector` scores positively over the
    same archetypes — over a fixture where a member card appears as a *second printing*, so the
    `Card#fingerprint` keying is exercised and a name-keyed copy goes red. Asserting only the
    "secondary absent disqualifies" clause leaves three others (the `joins(:primary_card)`
    restriction, the `points.positive?` filter, the fingerprint keying) unpinned.

**The store and the plan (B)**

13. **Both indexes, separately, as `assert_raises(ActiveRecord::RecordNotUnique)` on a
    `save!(validate: false)`**: two `(284, nil)` rows and two `(284, 3)` rows. A bare `assert_raises`
    is satisfied by the Ruby validation; testing only the nil case ships an implementation that lets
    a variant be mapped twice, after which `by_reference`'s Hash silently keeps the last one.
13a. Destroying an `Archetype` a mapping points at destroys the mapping and **does not 500** —
    `Admin::ArchetypesControllerTest`, on an archetype carrying **no** tournament standings, because
    `restrict_with_error` on `:tournament_standings` otherwise refuses the destroy before the
    foreign key is ever reached and the test proves nothing. `test/fixtures/archetypes.yml`'s own
    note pushes you toward exactly the fixture that hides this.
14. A row whose `archetype_key` has no mapping is planned `:blocked`, with the reason naming the
    deck label.
15. A row whose key *is* mapped carries that archetype on its `RowPlan`, and the importer writes it
    — **over a differing run archetype**: `StandingsImporter.call(archetype: a)` on a `RowPlan`
    carrying `b` writes `b`. Nothing else distinguishes `row_plan.archetype || @archetype` from the
    inverted order.
15a. An `:enrich` row carrying a *different* archetype leaves the existing standing's archetype
    alone and counts as `enriched` — pinning the discard as a decision rather than an omission.
16. The three divisions' counts land in their three columns.
17. **Fill-only-nil, over a fixture that has something to overwrite.** `tournaments(:one)` carries
    all four counts nil, so a test built on it cannot tell "fills nil columns" from "overwrites
    everything". Pre-set `masters_participant_count: 999` and `tier: "league_cup"`, import counts
    `{"masters" => 3122, "senior" => 364}`, and assert 999 and `league_cup` survive while
    `senior_participant_count` becomes 364.
17a. A second run **after the event has been renamed** finds the same event by `external_key` and
    does not create a second Tournament on that date.
18. The online source still writes its attendance to `open_participant_count` after
    `participant_count` became `participant_counts`.
19. `StandingsImporter` with neither a run archetype nor a row archetype writes nothing and says so;
    with `archetype: nil, deduplicate: true` it raises `ArgumentError` at construction.
19a. **The new source refuses rather than guesses when its published pool code names no
    `StandardPool`.** After the `standard_pool_for` guard moves from `@online` to `@standard_pool`, a
    non-online run with no pool falls straight through to `StandardPool.at(date)` — which would
    answer a pool, confidently and wrongly. Assert the event is **blocked** and its
    `standard_pool` nil, on a date where `StandardPool.at` *would* have answered
    (`2026-02-20` → `standard_pools(:twm_por)`).

**The screen (C)**

20. A non-admin cannot reach it.
21. A tournament id that is not a number is refused before anything is fetched.
22. **Count the fetches, not the rendered rows.** Stub the decklist service with a lambda appending
    each key to an array, preview a fixture whose 6 rows carry 2 distinct deck references, and
    assert the array has size **2** — not merely `uniq.size == 2`, which an implementation fetching
    all 6 and grouping afterwards also satisfies. That count is the feature's whole latency claim.
23. A reference already in `limitless_archetype_mappings` is shown as confirmed and its list is not
    fetched.
23a. The plan really is built with `max_rows: 1000` — captured from the keyword, asserted as the
    number — and a 400-row plan is **not** refused as `PlanTooLarge` for this source while it still
    is for the paper one.
24. Confirming persists the mappings **and** enqueues the job; confirming with a reference left
    unmapped still enqueues, and that deck's rows are reported as blocked.
25. The confirm form carries the mapping selections back, and `create` re-validates them — an
    archetype deleted between the two clicks does not 500.
25a. **The archetype guard becomes source-conditional and the two existing sources keep it.** Every
    one of the 12 tests in `standings_imports_controller_test.rb` passes `archetype_id`, so removing
    the guard outright breaks nothing today. Add: `preview` with `deck_id` and no `archetype_id`
    re-renders the form with the "Pick the archetype" alert, and `create` likewise redirects with
    `assert_no_enqueued_jobs` rather than 500ing inside `import_label`'s `@archetype.name`.
26. System: the screen works at both sides of the 768px breakpoint.

---

## 3. Order

1. The migration, the model and the fixtures are in (commit `c37e219`).
2. Lane A, with the suite to itself.
3. Lane B, likewise — it consumes A's names but edits none of A's files.
4. Lane C, likewise.
5. I run the five CI gates on the whole branch.
6. Sabotage every new test.
7. Three reviews.

## 4. Known risks, to be measured rather than assumed

- ~~**The preview's latency.**~~ Settled by measurement: 45 per-list requests would have cost 37 s,
  the bulk page costs one request and 0.6 s of parsing. See the spec's §4.
- **246 MB of RSS for one page**, in a Solid Queue worker that also holds the Rails app. Measured on
  the largest event Limitless currently lists (3122 players, 559 published rows); NAIC 2026 is
  3752. Confirm the worker survives it before claiming the feature works at scale, and say so in
  `CLAUDE.md` rather than leaving the next reader to find it.
- **`participant_count` → `participant_counts` touches the online source.** Its existing tests are
  the guard; if any of them needs editing to pass, that is a behaviour change and it stops the lane.
- **The five-consecutive-failure abort is now moot for this source** — a transport failure happens
  once, up front. Confirm it still behaves for the two sources it was written for.
- **The `@online` boolean does four jobs** (partitioning, external key, tier forcing, pool override).
  This plan unbundles only the pool override. The other three stay coupled and a fourth source
  would have to finish the job.
