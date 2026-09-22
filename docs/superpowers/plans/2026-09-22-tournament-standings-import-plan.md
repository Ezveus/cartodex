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

Indexes: UNIQUE `(limitless_deck_id, limitless_variant)` **and** a partial UNIQUE on
`limitless_deck_id WHERE limitless_variant IS NULL`. SQLite treats NULLs as distinct, so the
two-column index alone lets one base deck take a mapping row per confirmation.

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
- Three pages per event; a division page that 404s or holds no table is skipped, not fatal.

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

Containment picks the candidates exactly as `Decks::ArchetypeDetector#match_existing` does; the
ranking is `[-name_overlap, -score, name]` and `:decided` requires a strict lead on the first two.
`archetype` is nil for every verdict but `:decided`.

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

Lanes are disjoint by file. Every lane is **write-only** — the host cannot run the suite and the
test database is one shared SQLite file with no `TEST_ENV_NUMBER`, so two agents running tests
would cascade into `SQLite3::BusyException`. Each lane writes its tests and its code; **I** run the
suite in the container, serialised, after integrating.

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
7. A page with no table raises `ParseError` naming the URL.

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
10. Zero overlap with every candidate yields `:name_says_nothing`, not the highest score.
11. Containment finding nothing yields `:no_candidate`.
12. The candidate set is exactly `Decks::ArchetypeDetector`'s — an archetype whose secondary is
    absent from the list is not a candidate at any overlap.

**The store and the plan (B)**

13. Two confirmations of the same base deck (`variant` nil) make one row, not two — the partial
    index. *(Assert on the second `create!` raising, not on a count: a count passes on a database
    that never had the index.)*
14. A row whose `archetype_key` has no mapping is planned `:blocked`, with the reason naming the
    deck label.
15. A row whose key *is* mapped carries that archetype on its `RowPlan`, and the importer writes it.
16. The three divisions' counts land in their three columns.
17. An event found by `(name_normalized, date)` keeps a tier/format/pool/count a member set, and
    only nil columns are filled.
18. The online source still writes its attendance to `open_participant_count` after
    `participant_count` became `participant_counts`.
19. `StandingsImporter` with neither a run archetype nor a row archetype writes nothing and says so.

**The screen (C)**

20. A non-admin cannot reach it.
21. A tournament id that is not a number is refused before anything is fetched.
22. The preview lists one mapping line per distinct deck reference, not one per row.
23. A reference already in `limitless_archetype_mappings` is shown as confirmed and its list is not
    fetched.
24. Confirming persists the mappings **and** enqueues the job; confirming with a reference left
    unmapped still enqueues, and that deck's rows are reported as blocked.
25. The confirm form carries the mapping selections back, and `create` re-validates them — an
    archetype deleted between the two clicks does not 500.
26. System: the screen works at both sides of the 768px breakpoint.

## 3. Order

1. I write the contract stubs and the migration, and push the branch.
2. Lanes A and B in parallel (disjoint, both write-only).
3. I integrate, run the unit suite in the container, and fix what does not compose.
4. Lane C.
5. I integrate, run the five CI gates.
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
