# Importing the online "best finishes" (issue #153)

`play.limitlesstcg.com` publishes, per archetype and per card pool, a leaderboard of that
archetype's best online finishes. It is the other half of the sample `/archetypes/:id` reports
over: today the only source is `limitlesstcg.com/decks/<id>/results`, the paper events.

Everything below was measured against the live source on 2026-09-05 rather than inferred from
`tmp/limitless_scraper.py`, the reproduction of the pipeline this feature came from — whose
docstring is wrong on two points that would each have produced silently bad data. The
measurements are named where they decide something.

---

## What the source actually is

`play.limitlesstcg.com/decks/<slug>?format=standard&rotation=<year>&set=<SET>`

- A **top-20 leaderboard**, not a field. 20 rows whatever the parameters; a rare archetype
  returns fewer (`alolan-exeggutor-ex` → 2). No pagination, no "load more", one `<table>`.
- An invalid `(rotation, set)` pair returns **0 rows**, not an error. An unknown slug is a 404.
- Every row is a `<tr>` carrying `data-player`, `data-tournament`, `data-date` (ISO 8601 UTC),
  `data-place`, `data-score`.

### Two traps in that markup

**`data-place` is not the placement.** It is the row's rank in the leaderboard: the 20 rows carry
exactly 1..20 in order. The real finish is in the fourth cell's text — `data-place="13"` sits on a
row reading `2nd of 197`. An importer that reads the attribute records a second place as a
thirteenth.

**`data-score` is only the wins.** The fifth cell's text carries the full `W - L - T`
(`8 - 0 - 0`), matching `\d+ - \d+ - \d+` on 20/20 rows.

The fourth cell also carries the **attendance** (`1st of 259`), present on 20/20 rows — a figure
the paper source does not publish and which is why all three `*_participant_count` columns are
nil on every event imported so far.

### The player's identity is the URL slug, not the displayed name

20 rows carry 13 distinct display names but **12 distinct slugs**: `JRobrueda` and `Jose Rueda`
are one person, `jrobrueda`. Anything keyed on the displayed name splits them.

### The decklist page

`play.limitlesstcg.com/tournament/<tid>/player/<slug>/decklist`, laid out as
`.decklist .column .cards` with a `.heading` per column and one `<p><a>` per line.

**Only the Pokémon lines carry `(SET-NUM)` in their text.** `4 Crispin`, `2 Boss's Orders`,
`7 Grass Energy` carry nothing — the set and number exist **only in the `href`**
(`limitlesstcg.com/cards/<SET>/<NUM>`), present on 16/16 lines of the list measured. The scraper's
docstring claims every line is `N Card Name (SET-num)`; parsing the text as it says loses the
printing of every Trainer and Energy in every list.

The column headings give per-column subtotals (`Pokémon (19)`, `Trainer (27)`, `Energy (14)`)
beside the 60-card total, so there are three independent checks on a parse.

---

## The decisions

### 1. The dedup is a precondition, not a follow-up (#158)

Measured over the 20 rows of `raging-bolt-ogerpon` at `set=PBL`:

- **8 distinct 60-card contents for 20 rows.**
- **`jrobrueda` holds 8 of the 20 rows**, six of which are the *identical* 60 cards — one list
  entered into six weekly online tournaments — plus two more identical to each other.
- `aruarupokeka` holds 2 rows carrying 1 list.

Imported as they stand, one person's deck would be counted six times in the card report, and
every card in it weighted 6/20 = 30 % of the sample by one player's registration habit. So this
import writes **de-duplicated** rows: a `(player slug, list content)` pair is kept **once**.

Keyed on the **slug**, because the display name splits `jrobrueda` in two. Keyed on a **sorted
multiset of `(set, number, quantity)`**, not on the decklist text: the text is in DOM column
order, so one 60 laid out differently survives a string comparison. (The measurement above is
already the normalized figure — it was taken on sorted card maps — so it transfers.) Measured
effect on this leaderboard: **20 rows → 13**.

Lists identical across *different* players are **kept** — three such groups here. That is the
reference pipeline's own default and its reason holds: two people arriving at one 60 is a fact
about the build, not noise. A row carrying no decklist at all has no content to compare and is
likewise kept.

#### It is a pre-pass, and that is what makes it correct rather than merely cheap

The obvious implementation — check each row as the importer reaches it — is wrong three times
over, and all three failures have the same cause: the importer does not see the run whole.

- **It cannot keep the best finish.** `StandingsImportPlan` regroups rows by event and re-sorts
  them twice (`events.sort_by(&:date).reverse`, then `capped`'s sort by placement *within* an
  event), and `import_event` is the loop unit. `jrobrueda`'s six identical lists sit in six
  *different* events, so "the first one met" is decided by event date descending. The survivor
  would routinely not be the best finish — and "the leaderboard's own order" is not the finish
  either, since `data-place` is a rank (see the traps above).
- **It is not idempotent.** A row whose standing already exists and already has a list is `:skip`,
  and a `:skip` row never fetches its decklist. So on a second run of the same leaderboard the 13
  survivors are skipped without their content ever entering the comparison, the 7 dropped rows
  are compared against an empty set, and all 7 are created — the exact 30 % weighting this
  section exists to prevent, arriving on the second click.
- **It leaves empty events behind.** `import_event` calls `find_or_create_tournament` before it
  looks at a single row. Online rows are ~1 per event, so every dropped row would leave a
  `Tournament` nothing points at — and `StandingsImportUndo` deliberately never deletes events,
  there is no admin tournaments screen, and an online event is not in the catalog or in search, so
  nothing could ever remove them.

So the run begins by fetching the decklist of **every row of every unblocked event, `:skip` rows
included**, and grouping the lot. The winner of a group is the lowest `placement`, ties broken by
earliest date then by the event's own id — a total order that reads off the source alone.

The consequence is that **which rows survive is a pure function of the leaderboard** — run the same
page twice and the same 13 are chosen, the second run finds them present and skips them, the same 7
are dropped again.

#### That invariant is necessary and it is not sufficient — the key is in the database

An adversarial review reproduced the hole and it is the important paragraph of this document. The
pre-pass is pure in the *leaderboard*; the **database is not**, because the leaderboard is a rolling
top-20 that moves. When the survivor a run elected later falls off the board — twenty better
finishes appear, which is the ordinary life of a live page — the next run elects a different member
of the same group, does not find it, and creates it. The first survivor's row stays. Measured:

```
run 1  rows W1@4, W2@7, W3@9  → created 1, duplicates 2   standings [W1]
run 2  rows W2@7, W3@9        → created 1, duplicates 1   standings [W1, W2]
```

One player, one 60, two lists in the sample. Two smaller doors onto the same accretion, because the
group is only ever "this run's rows": an admin who splits a large run with `event_filters` (the
natural way around the 300-row cap) de-duplicates only *within* each filter; and a single transient
fetch failure leaves its row un-keyed and therefore kept, so the next healthy run enriches it rather
than removing it.

So the dedup key lives **on the standing**, not only in memory: `player_slug` and `list_digest`, both
nullable, both written by the online importer alone. A NULL is "not an online import" and never
participates. The check becomes one indexed lookup against
`(archetype_id, player_slug, list_digest)` *before* the in-run grouping, so a row whose twin is
already recorded is dropped whatever page, filter or run produced it.

Without that column "de-duplicated" is a property of one run against one snapshot of a page that
moves, and the archetype card report is what pays for the difference.

Rows are dropped **before** `import_event`, so an event left with no surviving row is never
created. The prefetch is what the run would have spent on those rows anyway, and its cost is
bounded by the same `max_rows` ceiling; for this source it is at most 20 requests, because the
leaderboard is at most 20 rows.

It still cannot live in `StandingsImportPlan`: that service never fetches, and making it do so
would turn the admin's preview — a GET — into 21 HTTP requests. The preview therefore shows the
row count before de-duplication, and the run reports `duplicate` as its own count beside created /
enriched / skipped. A decklist that fails to fetch during the prefetch has no content, is kept,
and fails again on its own row where it is reported by name.

### 2. The pool comes from the `set` parameter, never from the date

`StandardPool.at(date)` reads `legal_on` — the date Play! Pokémon considers a pool legal, about
two weeks after the cards ship. Online tournaments follow the **release**, not that legality.

Measured: for 3 of the 20 rows (2026-07-28/29/30) `StandardPool.at(date)` answers `TEF-CRI` while
the leaderboard the lists came from is `set=PBL`, whose `legal_on` is 2026-07-31. Anchoring by
date would file those three lists under the previous pool, where they would appear in a sample
whose other lists could not legally contain their cards.

The `set` parameter names the pool — `StandardPool.joins(:last_card_set).where(card_sets: { code: })`
resolves `PBL` to `TEF-PBL` — so the anchor needs no date reasoning at all. A `set` that resolves
to no pool blocks the run, the way a missing pool already blocks the paper import.

It resolves to **exactly one pool or the run is blocked**, and a `.first` would be wrong: the
UNIQUE key is `(first_card_set_id, last_card_set_id)`, the *pair*, so two pools may legitimately
share a last set — which is what a rotation landing between two set releases produces, moving the
first bound while the last stays put. Today's nine pools happen to have nine distinct last sets,
so `.first` would look correct right up until it silently was not. Two matches is a refusal naming
both, not a coin toss.

### 3. Online events are catalogued but not listed

A standing needs a `Tournament` (`tournament_id` is `NOT NULL`), so these events become rows. The
objection recorded when this source was first refused was about the **public catalog**, not about
the statistics: 20 events per archetype per pool would bury the handful of events members actually
attend.

So `tournaments.online` (boolean, `NOT NULL`, default `false`) is excluded from
`TournamentsController#index` and from `Search::Global#tournament_scope`, and nothing else
changes. In particular:

- `#show` stays reachable. An event's existence is not a secret — hiding it would be a new rule,
  and the archetype pages are the only thing that leads anywhere near it.
- **No policy gains a clause**, but the page does. A policy rule would be a rule to keep true
  later; what actually needed fixing is that `tournaments#show` *invites* the wrong thing. It
  renders "Record another participation" for any member holding a `TournamentProfile` — offering
  to attach a Play! Pokémon **age-division** profile to an event this very spec has just declared
  has no age divisions — and `Tournaments::Standings::Row` renders "This is me" on every unclaimed
  row. So the entry and claim affordances are withheld on an online event.

  Withheld rather than refused, because the consequence is not cosmetic: `Tournament has_many
  :entries, dependent: :restrict_with_error`, so one member recording one participation makes an
  imported online event permanently undeletable. Nothing here refuses a member who reaches the
  route anyway; the page simply stops proposing it.

  Three invitations, not two: "Publish my participation" creates a *standing* from an existing
  entry rather than a new entry, and it is part of the same participation model that means nothing
  online, so it goes with them.

  What is withheld is the **invitations**, not the record. A member who already holds a
  participation at that event keeps the link to it — blanket-hiding the section would hide an
  existing entry from the only page that links to it, which is the bug the plural `my_entries`
  work fixed.

- **And the page has to say why**, which an earlier draft of this section left out entirely. It
  enumerated what stops being proposed and never asked what the event's own fiche then looks like:
  Date, Tier, Format and nothing else, so an imported weekly renders as an ordinary event with
  three missing buttons, a sheet whose only division heading is "Open", and a "Back to Tournaments"
  link to a catalog this very decision removed it from. Four absences with one cause and no cause
  given reads as a bug. `Tournaments::EventDetails` therefore prints a **Venue** row on an online
  event, with the sentence that explains the other three — a detail row and not a header badge,
  because it is a fact about the event like its date, and the participation page renders the same
  component.

  There is deliberately **no form control for `online` and no `tournament_params` permit**, and the
  parallel with `open_participant_count` does not hold: that is a scraped number that can be wrong
  and that caps every placement above it, while this is a fact about which importer wrote the row.
  A checkbox would let any member move an event into or out of the public catalog, which is the one
  thing the column is for.

### 4. Divisions: a fourth value, and a narrower list for forms

Online play has no age divisions, and `tournament_standings.division` is `NOT NULL` behind
`enum … validate: true`. Writing `masters` would be a lie that `Archetypes::Performance#by_division`
then reports as fact.

`TournamentStanding::DIVISIONS` stops being `TournamentProfile::DIVISIONS.map(&:to_s)` and becomes
`%w[junior senior masters open]` in its own right, with `AGE_DIVISIONS` keeping the old three.
The split matters because the two lists answer different questions and four readers disagree
about which they want:

| reader | list |
|---|---|
| the enum, `division_order`, `Standings::Table`, `Performance#by_division` | `DIVISIONS` |
| `Tournaments::Standings::Form`'s select | `AGE_DIVISIONS` on a paper event, `open` on an online one |
| `prefill_attributes` | `AGE_DIVISIONS` |

The form's entry is per **event**, not one list — an earlier draft of this table wrote it flat and
that was the bug's hiding place. The paragraph below fixes only the *edit* case, by adding the
row's own value; a **new** row has no value to read, so on an online event a flat `AGE_DIVISIONS`
offers three age divisions and nothing else, and the member adding a missing row to an imported
sheet files an online result as a Junior. The two lists are mutually exclusive per venue, which is
this section's rule in mirror: offering junior/senior/masters on an event that has none is the same
lie in the other direction.

A member typing a paper sheet must not be offered "Open"; a report covering online events must not
drop them.

**The select must also carry the row's own division, and that is not a detail.** The form is
shared by new *and* edit, standings are wiki-governed, and `standing_params` permits `:division`.
A select built from `AGE_DIVISIONS` alone renders no option matching `"open"`, so the browser
pre-selects the first — Junior — and a member who opens an imported online row to fix a typo in a
player name silently refiles an online result as a Junior one on save. That is precisely the lie
this section refuses to let the importer write, arriving through the front door instead. The
options are `AGE_DIVISIONS` plus the record's own value when it is not one of them.

### 5. Attendance, wins, losses and ties are written because the source has them

`tournaments.open_participant_count` joins the three age-division columns and is registered in
`DIVISION_COUNT_COLUMNS`, so `placement_within_division_field` keeps working for an online row
(placement 1 against a field of 259). `wins`/`losses`/`ties` are written on the standing from the
score cell — columns that exist, that nothing has ever written, and that the source hands over.

`open_participant_count` is not one constant but **five hand-written places**, and four of them
are easy to miss: `DIVISION_COUNT_COLUMNS`, the `numericality` validation that would otherwise let
the importer write `-3`, `tournament_params`, `Tournaments::Form`'s field-size inputs — and that
group's own label, "Field size per **age** division", which becomes false the moment the Open
input joins it. The
last two matter more than they look: `placement_within_division_field` *caps* a placement against
this column, so a wrong value written by an import makes every standing above it unsavable through
the wiki edit form — and with no input on the event form there would be no way anywhere in the app
to correct the number.

**No win rate is computed here**, and that is a page belonging to its own issue — but "no UI reads
them" would be false: `TournamentStanding#record_label` is already rendered in the standings
sheet's Record column, so an imported online row shows its W-L-T there the day this ships. Two
written statements become false with it and are corrected in the same commit: the class comment on
`Archetypes::Performance` ("`Tournaments::StandingsImporter` never writes wins/losses/ties …
exactly 1 of 94 standings carries a W-L-T") and CLAUDE.md's matching paragraph.

### 6. The tier is forced, never guessed

`StandingsImportPlan::TIER_PATTERNS` reads event names, and online event names are arbitrary
(`Pumpkaweekly`, `TOURNAMENT OF DOOM! WORLDS LCQ!`, `👑 CrownOfSpain 👑 #4`). Measured: all 20 fall
through to `other` today — but a name containing "Regional" would be filed as a Regional, and
`Tournament::CP_REFERENCE` would then offer Championship Points for an online event. Online events
are written `tier: "other"` unconditionally.

### 6b. An online event is identified by its own id, not by its name and date

`Row#event_key` carries the tournament's own Limitless id, and until an adversarial review said so
**nothing read it**: the plan still grouped on `[event_name, event_date]`, which is the paper
source's identity rule. Online event names are arbitrary and repeat weekly — `Pumpkaweekly`,
`CrownOfSpain #4` — so two genuinely different tournaments on one day merge into a single event.
Measured: two rows from two events plan as one, the event takes its `participant_count` from
whichever row came first, and the other event's row is then refused for a placement above a field
size that was never its own.

So an online event is keyed on `event_key`, stored as `tournaments.external_key`. Which forces the
catalog's own identity rule to become explicit rather than universal: `(name_normalized, date)`
UNIQUE becomes **partial**, `WHERE online = 0`. That rule is about the public catalog — two members
must not catalogue one event twice — and it was never a claim about the world. A second partial
UNIQUE index on `external_key WHERE external_key IS NOT NULL` is what actually keeps one online
event to one row (partial, because SQLite treats NULLs as distinct — the trap `Archetype`'s old
index fell into).

### 7. The archetype pages must say how much of the sample is online

This is the deepest consequence and the one that would otherwise ship silently, because **nothing
in the suite goes red for it**.

`Archetypes::MetagameScope` buckets standings on `tournaments.standard_pool_id` alone. An online
event anchored to `TEF-PBL` lands in the *same bucket* as a Regional anchored to `TEF-PBL`, so
"TEF-PBL — 16 lists" would blend 13 online weeklies with 3 Regionals, and the card report's
percentages would describe a mixture the page never names. The archetype feature's own spec argues
at length that pool scoping "is not a refinement, it is the difference between a true report and a
false one" — this adds a second axis of blending along exactly the same reasoning.

`Archetypes::Performance#totals` has the same problem in miniature: its "N events" is
`COUNT(DISTINCT tournament_id)`, which now mixes a weekly online tournament with a Regional; and
because §6 forces `tier: "other"`, `by_tier` files every online event in the same "Other" bucket
as a genuine paper one, indistinguishable. `Archetypes::IndexCounts` feeds the catalog's "events"
column and its "last event" date, and the archetype index is ordered by standings count — so
which archetype leads the index starts depending on which *kind* of import somebody ran.

**The page says so.** `MetagameScope` and `Performance` count the online standings in their
sample and the archetype page names the figure. Splitting the sample by venue — a second
selector beside the pool one — is the better answer and is deliberately **not** in this change:
it is a page, it needs its own measurements once there is more than one archetype's worth of
online data, and shipping the import behind an unnamed blend to get there is the one thing that
must not happen in between.

---

## Shape of the change

The plan and the importer are already source-agnostic where it matters:
`StandingsImportPlan.call(rows:)` takes anything carrying the eight `Row` fields, and the importer
reads only `row.player_name / division / placement / list_url`. Two couplings are hard-coded and
become the seam:

- `StandingsImporter#attach_field_list` calls `Tournaments::LimitlessDecklist` by name;
- `LimitlessImportJob#build_plan` calls `Tournaments::LimitlessResults` by name.

New:

- `Tournaments::OnlineResults` — leaderboard → rows, carrying the extra fields (slug, attendance,
  W-L-T, online: true, standard pool code, forced tier).
- `Tournaments::OnlineDecklist` — decklist page → the `QUANTITY NAME SET NUMBER` text
  `Decks::Fetcher` already parses, taking set and number from the `href`.
- Three migrations. `tournaments.online`, `tournaments.open_participant_count` and a composite
  `(online, date)` index; `tournament_standings.player_slug` and `list_digest` with an index on
  `(archetype_id, player_slug, list_digest)` (§1, the stored dedup key); and
  `tournaments.external_key`, which turns `(name_normalized, date)` UNIQUE partial and adds a
  second partial UNIQUE index of its own (§6b). The division needs no migration at all —
  `division` is a string column and the enum lives only in Ruby. The `(online, date)` index does:
  `#index` becomes
  `where(online: false).order(date: :desc)` on the one table this feature fills with 20 rows per
  archetype per pool, and it is public, anonymous and rate-limited at 60/min. The plain date index
  cannot serve that filter, and CLAUDE.md's note on this very endpoint says what happens then —
  "60/min would have rationed an amplifier instead of removing it".

The admin screen is more than "a source choice": `DECK_ID_RE = /\A\d+\z/` guards a value
interpolated into a fetched URL, and the online source is a **slug** plus a `rotation` and a `set`
— three interpolated parameters needing three equally narrow guards. `#preview` rescues
`Tournaments::LimitlessResults::ParseError` by name; `Tournaments::OnlineResults::ParseError` is a
different constant, so a one-line source switch turns a bad slug into the 500 the comment beneath
that rescue says is not an acceptable answer.

`StandingsImportPlan`'s two lookups are **partitioned by venue**, which is not the same as reading
`Tournament.catalogued`. `load_catalogued` loads every event within ±3 days of the row range and
`similar_tournaments` is an O(events × catalogued) Ruby scan over it, so a paper preview must not
see online weeklies as "similar tournaments" noise and neither set may grow without bound as this
source is imported. But a blanket `catalogued` would contradict the idempotence argument in §1: an
online re-import could then never find the events its own first run created, so every survivor
would be planned `:create`, collide with `name_and_date_are_unique` and the standings UNIQUE key
row by row, and the run would report a wall of failures where it should have reported skips. The
database would gain nothing either way — which is exactly why a test worded only as "writes no new
rows" would pass while the property was gone. So a paper run looks at paper events and an online
run at online ones.

Changed: the importer gains a decklist service and a dedup step; the plan learns the online
classification; the admin form gains a source choice.

**`Import::KINDS` gains nothing.** The obvious move is an `online_standings` kind, and it is a
trap: `Tournaments::StandingsImportUndo#call` raises unless `@import.kind == "limitless_standings"`,
and `Admin::ImportsController#undo` gates on the same string literal — so a new kind would produce
runs that look identical in the admin table and silently cannot be undone. The two sources produce
the same receipt (`created_standing_ids` / `enriched_standing_ids`) and undo does the same work on
both, so both runs are `limitless_standings` and the `label` says which source they came from.

---

## Deliberately out

- **The `/decks` index aggregates.** That page publishes `Count / Share / Score / Win %` per
  archetype over the whole online field (`Dragapult 3090 7.58% 7844-6544-274 53.50%`) — the
  metagame share and win rate the archetype pages currently say are impossible. They are
  *Limitless's* aggregates over *their* field, not a figure this database can compute;
  republishing someone else's number under a heading reading "recorded in Cartodex" is a
  different decision and a different issue.
- **Dedup across pools, and it is a rule rather than an omission.** The stored key (§1) closes the
  churn and the split run — a (player, list) pair already recorded is dropped whatever page, filter
  or run produced it — and the lookup is **scoped to the pools the run targets**, so the same
  player's genuinely unchanged 60 is recorded once *per pool*.

  That is the deliberate half. The card report buckets on `tournaments.standard_pool_id`, so each
  pool is its own sample, and a list that survived a rotation untouched is a real row of *each*
  pool's leaderboard: de-duplicating across pools would make whichever pool was imported second
  report fewer lists than the source published — and a list that survives a rotation unchanged is
  exactly the one its player keeps registering, so the loss would land hardest on the pool that had
  just opened. A review found the code doing this and the design record forbidding it, which is the
  worst of both: the next reader trusts whichever they read first.

  (Not, as an earlier draft said, a second row at the *same* event — that is impossible, since
  `(tournament_id, player_name_normalized, division)` is UNIQUE and the plan marks it `:skip`.)
- **A venue axis on the archetype pages.** See §7: the blend is named on both `/archetypes/:id` and
  — since #160 — on `/archetypes`, where each row says how many of its results and events came from
  online play. Neither page lets a reader *separate* the two, which is what #160 tracks; the
  measurement recorded there argues against building the selector until a second pool holds both
  venues or a blended pool's paper half exceeds `SMALL_SAMPLE`.
- **A win rate anywhere**, though the data to compute one now exists.
- **Any online-only tournament reaching `/tournaments`, search, or the dashboard.**
- **Keeping online field lists out of `/decks/shared`.** Every imported row builds a `shared: true`
  ownerless `Deck`, and that public, authorless listing is the one surface this genuinely fills —
  13 lists per archetype per pool, indistinguishable from a paper field list or a member's own
  shared deck. It is not a new problem (94 paper lists are already there) but this multiplies it,
  and hiding ownerless field lists would change what that page means for the paper import too.
  Its own issue.

---

## Tests that must be written, because nothing existing goes red

An adversarial review of this spec measured the suite against every decision above. Almost the
whole of it stays green — including for the two defects that were real bugs — and that is itself
the finding. `Archetypes::Performance`'s "divisions are ordered junior, senior, masters" asserts an
exact array but holds no `open` row, so it stops guarding the moment a fourth value exists;
`public_access_test.rb`'s hard `Tournament.count` is unmoved because `online` defaults to false;
and "the division select defaults to masters" sits directly above the edit-form defect in §4
without asserting it.

So each of these needs a test that goes red without its fix, verified by sabotage:

1. The same leaderboard imported twice writes the same rows the second time (idempotence — the
   defect that would otherwise appear only on the second click).
2. The survivor of a duplicate group is the best *placement*, not the first row met.
3. An event whose only row is de-duplicated away is never created.
4. Editing an imported online standing through the wiki form and saving leaves its division
   `"open"`.
5. `tournaments#index` and `Search::Global` do not answer with an online event; `#show` still does.
6. An online event's page offers neither "Record another participation" nor "This is me".
7. `open_participant_count` round-trips through the event form, and refuses a negative.
8. The archetype page names the online share of its sample.
9. A bad slug, rotation or set is refused by the admin screen before anything is fetched, and an
   `OnlineResults::ParseError` re-renders the form rather than 500ing.
10. Two pools sharing a last set block the run instead of picking one.
