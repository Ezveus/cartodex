# Admin: importing a tournament's field from Limitless TCG

Status: design, 2026-09-05. Revised after an adversarial review that found six blockers in the
first draft; every decision below that changed says so.

## What this is for

`TournamentStanding` (PR #149) records one line of an event's public standings sheet. Every row
today is typed by hand. Limitless TCG already publishes those rows, and this feature lets an admin
pull them in in bulk.

The source is the page a Pokémon player already reads to research an archetype:
`https://limitlesstcg.com/decks/<deck_id>/results` — every notable finish of one deck across every
event Limitless covers, each with a player, a placement and (usually) a decklist.

## The shape of the source, as measured

Fetched and parsed on 2026-09-05 against deck 280 (Raging Bolt), 1.1 MB, one `<table>`:

- One `<th class="sub-heading" colspan=5>` per event, holding
  `<a href="/tournaments/518/SR">10th June 2026 - NAIC 2026, New Orleans (SR)</a>`.
- Then one `<tr>` per placement, always exactly five `<td>`: a format icon
  (`<img class="format" alt="standard">`), the place (`43rd`), the variant icons, the player
  (`<a href="/players/7363">Tomi Markkula</a>`), and the decklist link
  (`<a href="/decks/list/28788">`).

Measured over the whole page: 176 event headings, 1569 placement rows, **all** with five `<td>` and
a player link, 21 with no decklist, every place label matching `\d+(st|nd|rd|th)` and every date
prefix parsing. The only `href` division suffixes are `/JR` (38) and `/SR` (24); 114 headings carry
none. Formats seen: `standard` (1496), `standard-jp` (72), `expanded-jp` (1). Running the finished
parser against the live page yields 1569 rows, **116** distinct `(name, date)` events — the 60
missing headings are the JR/SR halves folding into their Masters event — and no nil anywhere.

A decklist page (`/decks/list/28788`) carries, per card:

```html
<div class="decklist-card" data-set="MEG" data-number="104" data-lang="en">
  <a class="card-link" href="/cards/MEG/104">
    <span class="card-count">4</span>
    <span class="card-name">Mega Kangaskhan ex</span>
```

inside a `[data-text-decklist]` block, and renders the same cards again under
`[data-image-decklist]` as `.decklist-visual-card` with the count as an `<img alt="4">` — no
`data-set`, no text count. Japanese and Korean events are normalised to **English** set codes
(`data-lang="en"` throughout list 27923, a `standard-jp` row), so issue #111's set-code collision
does not arise here.

## Decisions

**D1 — the source is the official site only.** `play.limitlesstcg.com` "best finishes" rows, which
the reference Python script also scrapes, are deliberately out of scope. They are online-only
tournaments ("Pumpkaweekly", "Pitch Black Tourney #10") with no age divisions and no place in a
catalog of real-world Play! Pokémon events; importing them would fill the public `/tournaments`
catalog with events a member cannot have attended, which is a product change and not an import.
The parsing layer is split so that adding a second source is adding one class.

**D2 — the archetype is the admin's, not the page's.** `tournament_standings.archetype_id` is
`NOT NULL`. A deck-results page *is* one archetype by construction, so the admin picks the matching
cartodex `Archetype` once and every row of the run carries it. Nothing is guessed and no archetype
is ever created. `Decks::Fetcher` still runs `Decks::ArchetypeDetector` on the imported list and
tags the *deck*; the standing's archetype is the admin's declaration and is never overwritten by
it — the rule `Tournaments::StandingListImportJob` already follows.

**D3 — the division comes from the `href` suffix, and the name loses it.** `/tournaments/518`,
`/tournaments/518/SR` and `/tournaments/518/JR` are one event with three age divisions, which is
how `Tournament` models it: three `*_participant_count` columns and a `division` on each standing.
So the suffix maps to `masters`/`senior`/`junior` and the trailing `" (SR)"` / `" (JR)"` is
stripped from the name. Getting this wrong is the single most damaging failure available here — it
would catalogue "NAIC 2026, New Orleans (JR)" as a separate public event, permanently, on every
import. The reference Python script does exactly that. A suffix `DIVISION_BY_SUFFIX` does not know
yields a **nil** division and keeps its name suffix, so a third division surfaces as a refused row
rather than being filed as Masters.

**D4 — tier and format are derived, and the preview shows what was derived.** *(new; the first
draft mentioned neither.)* `tournaments.tier` defaults to `regional` in the schema, so leaving it
alone would file Worlds as a Regional and hand a claimant 350 CP instead of 600 through
`Tournament::CP_REFERENCE`. It is derived from the event name by an explicit pattern table (worlds
/ international / regional / other) and shown per event in the preview, where the admin can see a
wrong guess before anything is written. Format comes from the row's own `<img class="format">`.
Limitless's `-jp` suffix has no cartodex enum value and mapping it to `standard` would force a
western `StandardPool` onto a Japanese event, which is the same lie D9 refuses in the other
direction — so `standard-jp` becomes format `other` with `other_format_name` `"Standard (JP)"`,
which needs no pool and records what is true.

**D5 — an event is found by an explicit query, not by `find_or_create_by`.** *(sharpened.)*
`(name_normalized, date)` is `Tournament`'s identity and its UNIQUE index, but
`find_or_create_by(name_normalized:, date:)` cannot work here: `before_validation :normalize_name`
recomputes `name_normalized` from `name`, which such a call leaves nil, so the create fails
validation and `find_or_create_by` returns an unpersisted record without raising. The lookup is
therefore `Tournament.find_by(name_normalized:, date:) || Tournament.create!(name:, date:, …)`, and
both it and the standing create rescue `ActiveRecord::RecordNotUnique` and re-find: the model
validations behind both UNIQUE indexes are non-atomic `exists?` checks, and a member typing a row
during the run, or two runs on two archetypes of one event, lose that race.

**D6 — an existing standing is never rewritten, but a missing field list is filled in.**
*(changed: the first draft skipped outright.)* `(tournament_id, player_name_normalized, division)`
is the standing's identity, and standings are wiki-governed — a member may have corrected the row,
and an import must not republish over that. But a hand-typed row carrying an archetype and no
decklist is *the common case*, and `deck_id` is `NULL` on it: attaching a list where there was none
overwrites nothing. So a run **creates** what is missing, **enriches** a row whose `deck_id` is
NULL when it has a list for it, and **skips** everything else — reported as three separate numbers,
because "30 enriched" and "30 skipped" are not the same result.

**D7 — every card is resolved before the deck transaction opens.** *(new; blocker.)*
`Decks::Fetcher` wraps its whole body in `serialized_transaction`, which on SQLite is
`BEGIN IMMEDIATE` — the write lock is taken at `Deck.create!` — and then calls `Cards::Fetcher`
per line, which fetches over HTTP for any unknown printing. A card page answers in ~0.7 s
(measured), so one list of new printings holds the app's single write lock for 15–30 s while
`config/database.yml`'s `timeout: 5000` makes every other writer raise `SQLite3::BusyException`
after five. Over a 300-row run that is a write outage for members. The importer therefore calls
`Cards::Fetcher` for every printing of a list **before** handing the text to `Decks::Fetcher`, so
that by the time the transaction opens every lookup is a local hit and the lock is held for
milliseconds. Nothing in `Decks::Fetcher` changes.

**D8 — a decklist becomes PTCG text.** The `data-set` / `data-number` attributes give exactly the
`QUANTITY NAME SET NUMBER` line `Decks::Fetcher::CARD_LINE_RE` wants. Guards, because that regex
fails **silently** — it wants `[A-Z]{2,3}` for the set code *and* `\d+` for the number, and drops
what it cannot match: the parser refuses a card with no printing, a set code outside
`/\A[A-Z]{2,3}\z/`, a number outside `/\A\d+\z/`, and a list whose quantities do not sum to 60. Each refusal names the card and fails that row alone. A run does create new `Card` rows
and does spend one HTTP request per unknown printing — the first draft's "nothing new touches
`cards`" was simply wrong.

**D9 — an event with no Standard pool is skipped, and says so.** `Tournament` requires a
`standard_pool` when the format is `standard`, and `StandardPool.at(date)` is nil for any date
before the earliest seeded pool's `legal_on` (2025-04-11). Inventing a pool, or silently
downgrading the format, would both write a lie into the public catalog. The event is listed in the
preview as unimportable with the reason, which is actionable: the admin adds the pool from
`/admin/standard_pools` and re-runs.

**D10 — the standing is written first, the list attached after, and the attach is confirmed.**
*(new; blocker. The confirmation was added after a second review.)* `update!` returns `true` even
when the row it targets has been deleted — Rails does not raise for an UPDATE that matched nothing
— and standings are wiki-governed while a run walks hundreds of them, so the write is read back
rather than assumed.
`Decks::Fetcher` commits its own transaction, so a list created before its standing is an orphan
the moment the standing fails validation — `placement_within_division_field` refuses a placement
above a field size the event already records, and that is reachable. `deck` is `optional:` on a
standing, so the order that cannot orphan anything is: create the standing, import the list, attach
it; and every failure path calls `destroy_if_ownerless` on whatever list was created, exactly as
`Tournaments::StandingListImportJob#discard_orphaned_list` already does.

**D11 — one bad row never fails the run.** Each row is written on its own; a failure (an
unparseable list, a placement above a recorded field size, an unreachable card) is collected and
the run continues. The `Import` row ends `completed` with the failures listed in `error_message`
when there were any, `failed` only when nothing could be done at all.

**D12 — a run can be undone, and undo lives beside the row it acts on
(`Admin::ImportsController#undo`).** *(new; blocker.)* Nothing else in the app can clean up after a bad
run: there is no admin tournaments controller, `Tournament has_many :entries,
dependent: :restrict_with_error` makes an event undeletable as soon as one member records a
participation at it, and an ownerless `shared` deck is reachable for deletion through
`TournamentStanding#destroy_ownerless_deck` and nothing else — while being listed publicly on
`/decks/shared`. So the run records the ids it created (`imports.created_standing_ids`, a JSON
column — the one migration this feature needs) and the admin panel offers "Undo this run", which
destroys the standings it created **that are still unclaimed**, takes their field lists with them
through the existing `before_destroy`, and reports the claimed ones it left alone. Events created
by the run are left standing: an empty catalog entry is harmless, and deleting one that another
member has since used is not this button's call.

**D13 — the plan is previewed, and the job refuses to import a different one.** *(sharpened;
the preview's HTTP verb changed.)* The preview is a **GET**, not the POST the first draft implied:
Turbo treats a non-redirected 200 answering a form POST as an error ("Form responses must redirect
to another location"), so a POST that renders the plan would do nothing at all in a browser, and
every render-a-body branch in this app is either a `422` or JSON. A GET is also reload-safe and
bookmarkable, which a POST-rendered plan is not. `GET …/preview` does the one HTTP request the
results page costs and renders the plan grouped by
event: rows to create, rows to enrich, rows already present, events that cannot be imported and
why, the derived tier, format **and division per row**, and two conflict flags — an existing `Tournament` within ±3 days
whose name is close but not equal (a duplicate the UNIQUE key cannot see), and a player already
recorded at that event in a *different* division (the same human, twice, which the key cannot see
either). The job re-fetches rather than trusting a plan carried through the browser, but the
confirm form carries the row count the admin actually saw and the job **refuses** if the refetch no
longer agrees: without that, Limitless publishing a new event between the two clicks silently
imports rows nobody approved.

**D14 — a run has a hard ceiling** (`max_rows:`, default 300). Above it the plan is refused with a
message asking for a tighter event filter or a lower per-event cap. It is a keyword rather than a
constant so a test can prove the refusal with two rows instead of a 300-row HTML fixture.

**D14b — a run that has stopped working stops.** *(new; revised after review.)* `HttpFetcher`
raises on any non-2xx, 429 included, and D11 collects per-row failures — so a rate-limited run
would otherwise end `completed` with 300 identical refusals. Five consecutive **rows** lost to a
transport failure abort it as `failed` instead. Per row and not per request: a row makes up to
sixteen of them and the card pages are fifteen sixteenths of the traffic, so counting only the
decklist fetch missed the requests a rate limit actually lands on — while a counter cleared by one
successful request would never reach five, since the decklist page can keep answering while the
card pages refuse. A list that merely will not parse is neither counted nor forgiven.

**D14c — a wrong division is not fixable by re-running.** *(new.)* The skip key of D6 includes
`division`, and `division` is derived. A run that got it wrong writes a second public row for the
same player at the same event on the corrected re-run, and the UNIQUE index cannot see it — which
is why the preview prints the derived division on every row, and why the parser refuses to guess
one it does not recognise (D3).

**D15 — scraping identifies itself and is bounded.** *(new.)* `HttpFetcher` sends a
`User-Agent` naming Cartodex with a URL, and replaces Net::HTTP's 60-second defaults with
10 s connect / 30 s read — a hung remote otherwise holds one of five Puma threads for a minute.
Timeouts and connection errors are rescued into `FetchError`, the class every caller already
handles (`CardsController#image` answers 502 with it rather than 500). It also refuses a URI that
is not `URI::HTTP`, which is the backstop behind the caller-side rule that the Limitless deck id
must match `/\A\d+\z/` before it is interpolated into a URL. The importer pauses between decklist
fetches (injectable, zero in tests).

**D16 — this kind of import cannot be retried from the imports table.**
`Admin::ImportsController#retry` refuses `standing_list` because the decklist text is not stored;
it refuses `limitless_standings` for the same class of reason — the run's filters are not stored —
and refusing explicitly is what keeps it from falling through the `case` into the wrong branch.
Re-running is one form submit away and, by D6, safe.

**D17 — imported rows are created by the admin who ran the import.** `created_by` is the admin, on
both the `Tournament` and the `TournamentStanding`, matching `TournamentsController#create`. A nil
creator would leave every imported event un-editable by anybody but an admin, since
`TournamentPolicy` answers `creator_or_admin?`.

## Contracts

```ruby
Tournaments::LimitlessResults.call(deck_id)          # => [Row]  (fetch + parse the results page)
Tournaments::LimitlessDecklist.call(list_url)        # => String (PTCG text, or ParseError)

Tournaments::StandingsImportPlan.call(
  rows:, event_filters: [], limit_per_event: nil, max_rows: 300
)                                                    # => Plan
# Plan#events           => [EventPlan]  ordered by date desc
# Plan#importable_rows, #total_rows, #count(:create|:enrich|:skip|:blocked), #over_limit?, #max_rows
# EventPlan             => name, date, tier, format, other_format_name, standard_pool,
#                          tournament (existing or nil), blocked?, blocked_reason,
#                          similar_tournaments, rows, importable_rows, count(status)
# RowPlan               => row, status (:create | :enrich | :skip | :blocked), reason, standing,
#                          other_division, importable?
# No `archetype:` — which archetype the rows carry only matters at write time.

Tournaments::StandingsImporter.call(plan:, archetype:, user:, pause: 0.0)
# => Result(created:, enriched:, skipped:, blocked:, standing_ids:, enriched_standing_ids:,
#           failures: [[label, message]], aborted_reason:) — #aborted?, #failed_count
Tournaments::StandingsImportUndo.call(import)        # => Result(destroyed:, detached:, kept_claimed:)

Tournaments::LimitlessImportJob.perform(import_id, user_id, options)
# options: deck_id, archetype_id, event_filters, limit_per_event, expected_row_count
```

| File | Role |
| --- | --- |
| `app/services/tournaments/limitless_results.rb` | fetch + parse the results page |
| `app/services/tournaments/limitless_decklist.rb` | fetch + parse one decklist into PTCG text |
| `app/services/tournaments/standings_import_plan.rb` | filter, cap, resolve events, classify each row |
| `app/services/tournaments/standings_importer.rb` | write the plan |
| `app/jobs/tournaments/limitless_import_job.rb` | run it against an `Import`, broadcast the summary |
| `app/services/tournaments/standings_import_undo.rb` | roll one run back |
| `app/controllers/admin/standings_imports_controller.rb` | `new` / `preview` (GET) / `create` |
| `app/controllers/admin/imports_controller.rb` | `undo`, beside the run it acts on |
| `app/views/components/admin/standings_imports/*` | the form and the plan table |
| `db/migrate/*_add_created_standing_ids_to_imports.rb` | the run's receipt (D12) |
| `db/migrate/*_add_enriched_standing_ids_to_imports.rb` | its other half (D12) |

`Import::KINDS` gains `limitless_standings`; its `label` is the archetype's name and the Limitless
deck id ("Raging Bolt — Limitless deck 280"), which is what the admin table's Label column and the
undo confirmation print. `imports.error_message` holds the per-row failure list, and the admin
imports table's Error cell becomes a `<details>` disclosure — it truncates to 60 characters today
with the rest in a `title=` tooltip, and `Ui::DataTable` stacks into a `data-label` grid below the
768 px breakpoint where there is no hover at all. `Admin::ImportsController#retry` becomes an
allowlist (`deck` and `card_set`) rather than a chain of refusals: its `case` has no `else`, so a
newly added kind silently destroys the row and enqueues nothing. `Ui::AdminNavbar` gains one `nav_link`, and
`test/controllers/navbar_active_section_test.rb` covers it — a page that lights no entry fails it.

## Tests

Scraping is only testable against frozen input, so the two parsers run against captured HTML in
`test/fixtures/files/limitless_deck_results.html` (both division suffixes, a row with no list, an
event predating every pool, a `standard-jp` row) and `limitless_decklist{,_incomplete,_unsupported_set}.html`
(faithful to the real page, image grid included). HTTP is stubbed the way the rest of the suite
does it — `HttpFetcher.define_singleton_method(:call)`, restored in `teardown` — since there is no
mocking library here. Every standing fixture points at `archetypes(:standings_marker)`, the rule
`test/fixtures/archetypes.yml` documents. The admin page gets a system test on both sides of the
768 px breakpoint, navigating with `click_nav_link`.

The tests that have to be able to go red, checked by breaking the implementation:
the `(JR)`/`(SR)` fold (D3), an unknown suffix not becoming Masters (D3), the set-code and
60-card guards (D8), the card pre-resolution leaving no HTTP inside the transaction (D7), the
enrich-don't-overwrite rule (D6), the orphan cleanup (D10), and the row-count drift refusal (D13).

## Out of scope, and one thing the next issue should look at

Attendance (the three `*_participant_count` columns) is never written — the results page does not
carry it, and neither are W/L/T records. Championship points, claiming an imported row, and the
online source (D1) all stay where they are.

**A sheet imported from one archetype's page is a partial sheet**, and nothing on the event page
says so — after importing deck 280 into NAIC, `/tournaments/:id` shows a sheet in which every
player played Raging Bolt. That is a property the feature shares with every hand-typed sheet (a
member types the rows they know), and the placements shown — 4th, 12th, 31st — do not claim to be
consecutive. It is called out here rather than fixed because marking a sheet partial means knowing
when it is complete, which nothing does.

**`tournaments#show` renders its standings sheet unpaginated** (`@tournament.standings.as_a_sheet`,
no limit, no pager, and deliberately no rate limit because it is "one page load per click"). That
is fine for a hand-typed sheet and stops being fine once ten archetypes have been imported into one
Worlds event.

*Resolved before merge.* It was built after all and merged into this branch, because a prerequisite
that lands separately is a window in which the feature is unusable at the scale it was written for.
The sheet pages at `TournamentStanding::SHEET_PER_PAGE`; `as_a_sheet` had to order the divisions in
SQL for a page boundary to fall where the reader sees it, and everything that points at a row now
points at the page it is on. See CLAUDE.md's paragraph on the sheet.
