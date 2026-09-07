# Bulk standings import from Limitless TCG

Turning one archetype's tournament history into `Tournament` and `TournamentStanding` rows, from two sources: the paper results pages and the online "best finishes" leaderboard.

This file carries detail that used to sit inline in `CLAUDE.md`. Everything here is a decision with a measurement behind it — read it before changing the code it covers, because most entries record something that was already tried and rejected.

Design records:

- `docs/superpowers/specs/2026-09-05-limitless-standings-import-design.md`
- `docs/superpowers/specs/2026-09-05-online-best-finishes-import-design.md`

---

**Bulk import of a field from Limitless TCG** (`/admin/standings_imports`) turns one archetype's
tournament history — `limitlesstcg.com/decks/<deck_id>/results`, measured at 176 event headings and
1569 placement rows for deck 280 — into `Tournament` and `TournamentStanding` rows. Five services
and a job, all two levels deep like every other service here: `Tournaments::LimitlessResults`
(fetch + parse the results page), `Tournaments::LimitlessDecklist` (one decklist → the PTCG text
`Decks::Fetcher` already parses), `Tournaments::StandingsImportPlan` (reads, never writes),
`Tournaments::StandingsImporter` (writes), `Tournaments::StandingsImportUndo`, and
`Tournaments::LimitlessImportJob`. The design record is
`docs/superpowers/specs/2026-09-05-limitless-standings-import-design.md`; the decisions that are
not obvious from the code:

**The `/JR` and `/SR` suffix on an event's href is an age division, not a different event.**
`/tournaments/518`, `/tournaments/518/SR` and `/tournaments/518/JR` are the three halves of one
tournament, and the heading repeats the suffix in the name — so it is stripped, and the 176
headings collapse to 116 events (measured against the live page). Left in, every import would add
a permanent second public catalog row per division per event, which is the one mistake here no
later correction undoes cheaply. A suffix `DIVISION_BY_SUFFIX` does *not* know yields a **nil**
division and keeps its name suffix, so a third division surfaces as a refused row instead of being
filed as Masters.

**The archetype is the admin's declaration, and the tier and format are guesses shown before they
are written.** `archetype_id` is `NOT NULL` on a standing and a deck-results page *is* one
archetype, so the admin picks it once; nothing is detected and no archetype is created (detection
still tags the *deck*, never the standing). `tournaments.tier` defaults to `regional` in the
schema, which would file Worlds as a Regional and then hand a claimant 350 CP instead of 600
through `CP_REFERENCE` — so it is derived from the name by a pattern table and printed per event in
the preview. Limitless's `standard-jp` becomes format `other` with `other_format_name`
`"Standard (JP)"`: writing it as `standard` would force a western `StandardPool` onto a Japanese
event, the same lie a missing pool is refused for. (The decklists are safe either way — Limitless
normalises even a Champions League list to English set codes, so issue #111 does not bite here.)

**An existing standing is never rewritten, but a NULL `deck_id` is filled in** — a row naming an
archetype with no list is the common case, and attaching one overwrites nothing, so a run reports
*created*, *enriched* and *skipped* as three different numbers. Enrichment is recorded on its own
half of the receipt (`imports.enriched_standing_ids`) because undo treats the two oppositely: it
deletes the rows the run *made* and only takes the field list back off the rows it did not.
Without that split an enrich-only run was unundoable in both directions at once — the receipt was
empty, and `standing_params` does not permit `deck_id`, so the member whose row it was could not
detach the list either.

**The preview is a GET and the job refuses a plan that has changed.** A POST that renders a body is
an error to Turbo ("Form responses must redirect"), and every render-a-body branch in this app is a
422 or JSON. The job re-fetches rather than trusting a plan carried through the browser, and the
confirm form carries the row count the admin saw: without that check, Limitless publishing an event
between the two clicks silently imports rows nobody approved. A run is capped (`max_rows:`, default
300 — a keyword so a test can prove the refusal with two rows) and gives up after five consecutive
*rows* lost to a transport failure. Per row and not per request, because a row makes up to sixteen
of them: the card pages are fifteen sixteenths of a run's traffic, so a rate limit that lets the
decklist page through and refuses those is still a run that has stopped working — and a counter
cleared by any one successful request would never reach five. A decklist that merely will not parse
is neither counted nor forgiven. The run records both halves of its receipt on the `Import`, and
**undo lives on `Admin::ImportsController#undo`**, beside the row it acts on: it destroys the
created rows nobody has claimed, takes the field list back off the enriched ones with
`update_column` (for the reason `#unclaim` uses it), keeps the claimed rows and says how many, and
leaves the events alone.
`Import::KINDS` gains `limitless_standings`, whose `tournament_id` stays nil because a run spans
many events, and `Admin::ImportsController#retry` became an allowlist (`deck`, `card_set`) rather
than a chain of refusals — its `case` has no `else`, so a new kind used to destroy the row and
enqueue nothing.

**`HttpFetcher` gained a `User-Agent` and real timeouts** (10 s connect, 30 s read, against
Net::HTTP's 60/60), and rescues timeouts and connection errors into `FetchError` — the class every
caller already handles, so `CardsController#image` still answers 502 rather than 500. It also
refuses a URI that is not `URI::HTTP`, the backstop behind the caller-side rule that a Limitless
deck id must match `/\A\d+\z/` before it is interpolated into a URL.

**Still out of scope, and worth knowing:** attendance and W/L/T, which the paper results page does
not carry. (`play.limitlesstcg.com`'s online "best finishes" *were* the other item here and are
now imported — see the next section, which is also where those two figures come from.)
Pagination of `tournaments#show`'s sheet *was* the prerequisite named here and
ships alongside this — see the paragraph on `SHEET_PER_PAGE` in
`docs/architecture/tournaments-and-standings.md`. A sheet imported from one
archetype's page is still a *partial* sheet and nothing says so; that is a property it shares with
every hand-typed sheet, and marking one complete would mean knowing when it is.

**The online "best finishes"** (`play.limitlesstcg.com/decks/<slug>?format=&rotation=&set=`) are the
second source for the same importer, chosen from the same admin screen. The plan and the importer
were already source-agnostic in shape — `StandingsImportPlan.call(rows:)` takes anything carrying
the eight `Row` fields — so the change is two parsers plus two keywords: `decklist_service:` on the
importer and `source`/`slug`/`rotation`/`set` in the job's options. `Import::KINDS` gains
**nothing**: `StandingsImportUndo`, `Admin::ImportsController#undo` and two places in the admin
imports view all gate on the literal `"limitless_standings"`, so a new kind would produce runs that
look identical in the table and silently cannot be undone — which is the only way back out of a bad
bulk run. The design record is
`docs/superpowers/specs/2026-09-05-online-best-finishes-import-design.md`.

**Three things in that markup are not what they look like, and each was measured rather than
inferred** — `tmp/limitless_scraper.py`, the only prior description of this source, is wrong on two
of them. `data-place` is the row's **rank in the leaderboard** (1..N in order), not the finish: a row
carrying `data-place="13"` reads `2nd of 197`, so reading the attribute files a second place as a
thirteenth. `data-score` is only the **wins**; the `W - L - T` is the fifth cell's text. And on the
decklist page only the **Pokémon** lines carry `(SET-NUM)` in their text — `4 Crispin`,
`7 Grass Energy` carry nothing — so the set and number come from each line's `href` and never from
its text, or every Trainer and Energy in every list loses its printing. `Tournaments::OnlineDecklist`
also checks each column against its own heading subtotal *before* the 60, because a column that
loses a line and one that gains one still sum to 60. A player is identified by the **slug in the
href**: 20 measured rows carry 13 display names for 12 slugs, `JRobrueda` and `Jose Rueda` being one
person.

**De-duplication is what makes this source usable at all, and it is a pre-pass rather than a per-row
check.** The page is a leaderboard of one player's *best finishes*, not a field: 20 rows hold **8
distinct 60-card contents**, and one player holds 8 of them with six carrying the identical 60 — one
list entered into six weekly tournaments. Imported as they stand, one person's deck is weighted at
30 % of the sample, and `COUNT(DISTINCT deck_id)` cannot see it because each standing gets its own
`Deck`. Deciding row by row is wrong three times over, all three because the importer never sees the
run whole: it cannot keep the best finish (`import_event` is the loop unit while the plan regroups by
event and re-sorts twice), it is **not idempotent** (a `:skip` row never fetches its list, so a
second run compares the survivors against an empty set and re-creates every row the first one
dropped), and it leaves an empty `Tournament` behind per dropped row — which `StandingsImportUndo`
never deletes and no screen can remove. So every row of every unblocked event, **`:skip` rows
included**, is fetched and grouped first, on `(player slug, sorted multiset of (set, number,
quantity))` — a multiset, because the decklist text is in DOM column order. Which rows survive is
then a pure function of the leaderboard.

**That invariant is necessary and not sufficient, and the gap is the whole reason
`tournament_standings.player_slug` and `list_digest` exist.** The pre-pass is pure in the
*leaderboard*; the database is not, because the board is a **rolling** top-20 that moves. When the
survivor a run elected later falls off it, the next run elects a different member of the same
group, does not find it, and creates it — the first row stays. Measured: run 1 over W1@4/W2@7/W3@9
writes W1 and run 2 over W2@7/W3@9 writes W2, one player's one 60 as two lists in the sample; three
runs of a board losing one row each time wrote three standings for one player's one list. Two
smaller doors onto the same accretion, because an in-memory group is only ever this run's rows: an
admin splitting a big run with `event_filters` (the natural way around the 300-row cap)
de-duplicates only within each filter, and one transient decklist fetch failure leaves a row
un-keyed and therefore kept, so the next healthy run *enriches* it instead of removing it. So the
key is stored — nullable, written by the online importer alone, indexed as
`(archetype_id, player_slug, list_digest)` — and checked in one `pluck` **before** the in-run
grouping, **scoped to the pools the run targets**. That scope is the difference between a true
sample and a short one: the card report buckets on `standard_pool_id`, so each pool is its own
sample and a 60 a player kept unchanged across a rotation is a real row of *each* pool's
leaderboard. Unscoped, whichever pool was imported second silently reports fewer lists than the
source published — and a list surviving a rotation untouched is exactly the one its player keeps
registering, so the loss lands hardest on the pool that just opened. **A NULL never participates**
— the paper source publishes no slug and two paper rows sharing a 60 are two real people who both
played it — which is why both columns are nullable and why the SQL excludes them rather than the
Ruby. Two more rules that are not obvious: a row is never a duplicate of its **own** standing (or a
plain re-import reports every row as `duplicate` instead of `skipped`), and the key is written on
the **enrich** path too, or a row whose first fetch failed stays un-keyed forever. `list_digest` is
a SHA-256 of the same sorted multiset the in-run key compares, through
`StandingsImporter.list_digest`, **one method**: two spellings of "the same 60" would drift and
cross-run de-duplication would stop silently while every run still reported duplicates within
itself. The ordering invariant is kept rather than inverted: it is `Decks::Fetcher` committing a
deck that creates an unreachable orphan, and fetching *text* commits nothing, so the prefetch may
go first while the deck build, `confirm_attached!` and `discard_orphaned_list` stay exactly where
they were. `StandingsImportPlan` still never fetches, so the preview shows the count *before*
de-duplication and the run reports `duplicates` as its own number.

**The pool comes from the `set` parameter and never from the date.** `StandardPool.at` reads
`legal_on` — when Play! Pokémon considers a pool legal, about two weeks after the cards ship — and
online play follows the **release**: measured, 3 of 20 rows dated before `PBL`'s `legal_on` would be
anchored to the previous pool, into a sample whose other lists could not legally contain their cards.
It must resolve to **exactly one** pool or the run is blocked, because the UNIQUE key is the bound
*pair* and a rotation landing between two releases leaves two pools sharing a last set. The tier is
likewise **forced** to `other` rather than guessed: online names are arbitrary, and one containing
"Regional" would be filed as a Regional and offered Championship Points through `CP_REFERENCE`.

**`tournaments.online` is catalogued but not listed**, through a `Tournament.catalogued` scope read
by `TournamentsController#index` and `Search::Global` — one archetype's leaderboard is 20 events and
the online index lists 139 archetypes, so left visible they bury the events members actually attend.
`#show` stays reachable (an event's existence is not a secret). **No policy gains a clause, but the
page does**: `tournaments#show` withholds its three participation invitations and the sheet's "This
is me" on an online event, because offering to attach a Play! Pokémon *age-division* profile to an
event with no age divisions is wrong, and `has_many :entries, dependent: :restrict_with_error` means
one member accepting makes the imported event permanently undeletable. Withheld, not refused — and
only the *invitations*: a participation the member already holds keeps its link. The migration's
composite `(online, date)` index is load-bearing: `#index` becomes `where(online: false).order(date:
:desc)` on the one table this fills with 20 rows per archetype per pool, and it is public, anonymous
and rate-limited at 60/min — the plain date index cannot serve that filter. `StandingsImportPlan`'s
lookups are **partitioned** rather than scoped to `catalogued`: a paper run looks at paper events and
an online run at online ones, because a blanket `catalogued` would stop an online re-import finding
the events its own first run created, turning every skip into a uniqueness failure.

**An online event is identified by `tournaments.external_key`, its own Limitless id, and not by
its name and date.** `Row#event_key` carried that id from the start and nothing read it: the plan
grouped on `[event_name, event_date]`, which is the *paper* source's identity rule. Online names
are arbitrary and repeat weekly ("Pumpkaweekly", "CrownOfSpain #4"), so two genuinely different
tournaments on one day merged into one event, which then took its attendance from whichever row
came first and refused the other event's rows for a placement above a field size that was never
theirs. The id **replaces** the pair in the group key rather than joining it — a key holding both
splits one event again the moment two of its rows spell its name differently — and
`find_or_create_tournament` and `catalogued_meanwhile` both key on it too, so a re-import finds
its own events. Which forces the catalog's identity rule to become explicit rather than universal:
`(name_normalized, date)` UNIQUE is **partial**, `WHERE online = 0`, with
`Tournament#name_and_date_are_unique` scoped to match (it returns early for an online record and
reads `Tournament.catalogued` for the clash) — that rule is about the public catalog, two members
must not catalogue one event twice, and it was never a claim about the world. A paper Regional and
an online weekly may now share a name and a date, and the online run writes onto its own row. A
second partial UNIQUE index on `external_key WHERE external_key IS NOT NULL` is what keeps one
online event to one row — partial, because SQLite treats NULLs as distinct, the trap `Archetype`'s
old index fell into.

**`TournamentStanding::DIVISIONS` gained a fourth value, `"open"`, and split from
`AGE_DIVISIONS`.** Online play has no age divisions and `division` is `NOT NULL` behind a validating
enum, so `masters` would be a lie `Archetypes::Performance#by_division` then reports as fact.
`AGE_DIVISIONS` stays derived from `TournamentProfile::DIVISIONS` — it must not drift from the list
that decides a real player's division — and `DIVISIONS` is those plus `"open"`. The split is what
keeps each reader honest: the enum, `division_order`, `Standings::Table` and `by_division` need all
four or an online row is silently dropped from a report that still looks complete, while the
standings form's select needs only the three **plus the record's own value**. That last clause is not
a nicety: the form is shared by new and edit, standings are wiki-governed, and `standing_params`
permits `:division` — so a select built from `AGE_DIVISIONS` alone renders no option matching
`"open"`, the browser pre-selects Junior, and a member fixing a typo in a player name silently
refiles an online result as a Junior one. `tournaments.open_participant_count` joins the three
age-division columns in `DIVISION_COUNT_COLUMNS` (so `placement_within_division_field` still caps a
placement), and it is **five** hand-written places, not one: that constant, the `numericality`
validation, `tournament_params`, `Tournaments::Form`'s inputs, and that group's own label, which
stops being "per **age** division" the moment Open joins it. Attendance and `wins`/`losses`/`ties`
are written because this source publishes all four — the first thing ever to write any of them.

**`/archetypes/:id` says how much of its sample is online**, and that is not decoration:
`Archetypes::MetagameScope` buckets on `tournaments.standard_pool_id` alone, so an online weekly and
a Regional anchored to the same pool land in the same bucket and the card report's percentages would
describe a mixture nothing names — the same defect the pool scoping itself exists to prevent, on a
second axis. Both counters ride inside the existing grouped queries (`COUNT(DISTINCT CASE WHEN
tournaments.online …)` in `MetagameScope#buckets`, two terms in `Performance#totals`), so
`/archetypes/:id` stays at its pinned query count (**16** when that was written, **17** since the card report began reading `card_label_assignments`). The events figure stays whole with the split
named beside it rather than split in two, because every other number on the panel is over the same
blended population. **Splitting the sample by venue — a second selector beside the pool one —
shipped as #160**, and it is this import that made it designable: nine archetypes now hold at
least eight lists on each side, and four of them carry cards whose inclusion differs by fifty
points or more between the halves. See `archetype-metagame.md`. **The index names it too**: `Archetypes::IndexCounts` carries
`online_standings` and `online_events` as two CASE terms inside the grouped query it already makes,
so `/archetypes` stays at its flat 7, and a row whose figures blend prints one muted sentence under
the badge. It names **both** ratios because they diverge — measured on the first archetype to carry
both sources, 13 of 106 standings but 13 of 16 events — so a note carrying only the standings share
invites the reader to map it onto the bigger number and read the blend as marginal, while the
events column is four fifths online and "Last event" is an online weekly. It is silent at zero
rather than dashed like the number columns, because an em dash there answers a question the reader
asked by looking at the column while a row with no online results has nothing to qualify — 61 of
62 archetypes in production. The all-online case gets its own sentence rather than an "Includes"
stating a mixture that does not exist, the same branch `Performance::Result#all_events_online?`
draws on the detail page. **The note lives in a wrapper `div`, and that wrapper is load-bearing**:
below 768px `.data-table` turns each row into a card whose cells are
`display: flex; align-items: center`, so a link and a note placed directly in the cell become two
flex items on one line — measured at 390px, the note took 109px of a 326px cell, right-aligned, and
grew the row from 29px to 64px. No request test can see that, and no system test visited
`/archetypes` before this one, which is why the mobile half of the CI sweep saw nothing; the test
now measures the two bounding boxes.

**Also out:** de-duplication across *leaderboards*. The stored key closes the churn and the split
run, but it is keyed on the archetype and not on the pool, so one player's unchanged 60 still
appears once per pool page imported — correct as far as it goes (a TEF-CRI list is not a TEF-PBL
list) and unmeasured either way. Also out: any win rate, and keeping online field lists out of
`/decks/shared`, which now receives one authorless shared deck per imported row.
