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

The consequence is the property that matters: **which rows survive is a pure function of the
leaderboard, not of what is already in the database.** Run it twice and the same 13 rows are
chosen; the second run finds them present and skips them, and the same 7 are dropped again.

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
| `Tournaments::Standings::Form`'s select, `prefill_attributes` | `AGE_DIVISIONS` |

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

`open_participant_count` is not one constant but **four hand-written lists**, and three of them
are easy to miss: `DIVISION_COUNT_COLUMNS`, the `numericality` validation that would otherwise let
the importer write `-3`, `tournament_params`, and `Tournaments::Form`'s field-size inputs. The
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
- One migration: `tournaments.online`, `tournaments.open_participant_count`, and a composite
  `(online, date)` index. The division needs no migration at all — `division` is a string column
  and the enum lives only in Ruby. The index does: `#index` becomes
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

`StandingsImportPlan`'s two lookups read `Tournament.catalogued` as well. `load_catalogued` loads
every event within ±3 days of the row range and `similar_tournaments` is an O(events × catalogued)
Ruby scan over it — so without the scope every *paper* preview would list online weeklies as
"similar tournaments" noise, and the set would grow without bound as this source is imported.

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
- **Dedup across leaderboards.** The pre-pass makes a run idempotent against itself, which is what
  fixes the re-import case. It does not span *different* leaderboards: the same player's same list
  reached through another pool's page is a different event and becomes a second row. (Not, as an
  earlier draft of this said, a second row at the *same* event — that one is impossible, since
  `(tournament_id, player_name_normalized, division)` is UNIQUE and the plan marks it `:skip`.)
  Closing it needs the player slug stored on the standing, a column this change does not add.
- **A venue axis on the archetype pages.** See §7: the blend is named, not yet separable.
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
