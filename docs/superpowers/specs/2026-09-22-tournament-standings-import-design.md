# Importing one whole tournament from Limitless TCG

Turning `limitlesstcg.com/tournaments/<id>` — a single real-world event's public standings sheet,
every division, every player — into one `Tournament` and its `TournamentStanding` rows.

This is the **third** source of `Tournaments::StandingsImportPlan` / `StandingsImporter`, beside the
paper archetype-history pages and the online best-finishes leaderboard
(`docs/architecture/limitless-imports.md`). It is also the first one whose rows do **not** share a
single archetype, which is the whole difficulty and most of this document.

Every number below was measured on 2026-09-22 against `https://limitlesstcg.com/tournaments/577`
(Regional Baltimore, MD, 19 September 2026) and the development database at 4916 cards /
81 archetypes. Nothing here is inferred from a comment or a docstring.

---

## 1. What the source actually publishes

One event is **three pages**, one per Play! Pokémon age division:

| Page | Rows | Attendance stated |
|---|---|---|
| `/tournaments/577` | 559 | 3122 |
| `/tournaments/577/SR` | 8 | 364 |
| `/tournaments/577/JR` | 8 | 233 |

**The attendance on a division page is that division's field, not the event's.** Measured on
`/tournaments/563` (Special Event Cape Town): the Masters page states `88 Players` while the SR and
JR pages state `? Players` — an event-wide total would have been repeated on all three. The three
figures therefore map one-to-one onto `tournaments.masters_participant_count`,
`senior_participant_count` and `junior_participant_count`, which is what
`TournamentStanding#placement_within_division_field` reads. `? Players` is a real value the parser
must yield as nil rather than as zero.

The markup is a single `<table class="data-table striped">` whose rows carry their data twice —
once as attributes, once as cells:

```html
<tr data-rank="1" data-name="Dylan Kasturi" data-country="US" data-deck="Basic Box">
  <td>1</td>
  <td><a href="/players/8258">Dylan Kasturi</a></td>
  <td><img class="flag" ...></td>
  <td><a href="/decks/339"><span data-tooltip="Basic Box">…</span></a></td>
  <td><a href="/decks/list/29001">…</a></td>
</tr>
```

The header carries the rest:

```html
<div class="infobox-heading">Regional Baltimore, MD <img class="flag" alt="US"></div>
<div class="infobox-line">
  19th September 2026 • 3122 Players
  • <a href="/decks/?time=all&format=TEF-PBL">Temporal Forces - Pitch Black</a>
</div>
```

Four consequences:

- **The format is stated, not inferred.** `format=TEF-PBL` is `StandardPool#name` byte for byte
  (`"#{first_card_set.code}-#{last_card_set.code}"`). The pool is therefore looked up by its two
  bound codes and **never** through `StandardPool.at(date)`. That is not a refinement: `.at` reads
  `legal_on`, so an event held in the fortnight after a set ships but before Play! Pokémon rules it
  legal would be anchored to the pool the source says it was not played under. The event that
  prompted this feature is exactly that case.
- **Every row carries a decklist, and one page carries all of them.** 575 of 575 on this event; a
  row without one is possible (`/tournaments/563` publishes 10 rows and 6 lists) and yields a
  standing with no field list, the common case the existing importer already handles. See §4 —
  `/tournaments/577/decklists` is the single page that changes this feature's whole cost.
- **No W-L-T and no attendance per row.** The paper source has none either; only the online
  leaderboard publishes them. They stay nil.
- **`data-country` is not stored.** `TournamentStanding` has no country column and adding one is a
  separate question.

## 2. The archetype is per row, and detection alone gets it wrong once in five

`tournament_standings.archetype_id` is `NOT NULL`. Both existing sources solve that by having the
admin declare one archetype for the whole run — a deck-results page *is* one archetype — and
`Tournaments::StandingsImporter` holds it as a single `@archetype` for the run
(`app/services/tournaments/standings_importer.rb:75`, written at `:399`). A whole event's sheet
holds **45 distinct decks over 575 rows**, so that contract has to change.

Three candidate rules were measured against real lists off this event.

**(a) The Limitless deck name, matched against `archetypes.name`.** Refused. Of the 45 names, **4**
match an archetype exactly, 5 have no plausible candidate at all, and token matching is wrong more
often than right — `Greninja` → *Mega Greninja ex / Dragapult ex*, `Metagross` → *Steven's
Metagross ex / Jellicent ex*, `Mega Chandelure` → *Mega Froslass ex / Chandelure*.

**(b) `Decks::ArchetypeDetector` on the imported list, as it stands.** Refused as a *sole* rule.
Over 56 sampled lists it matched 55 — and **12 of those matches are wrong**:

| Limitless deck | Detected | Why |
|---|---|---|
| Slowking (×2) | *Lillie's Clefairy ex* | a rule-box tech scores 3 against `Slowking`'s 2 |
| Alakazam Dudunsparce | *Lillie's Clefairy ex* | same, against `Alakazam`'s 2 |
| N's Zoroark | *Mega Lopunny ex* | 3–3 tie with *N's Zoroark ex*, broken by row order |
| Dhelmise (×3) | *…/ Banette* or *…/ Sinistcha* | 4–4 tie between two real archetypes |
| Basic Box (×6) | *Raging Bolt ex / Teal Mask Ogerpon ex* | 6–6 tie |
| Marnie's Grimmsnarl | — | the list plays no Froslass |

The detector was written to tag a deck a member is importing, where a wrong guess costs one click to
fix and the member sees it. Here the same guess lands in a public, wiki-governed sheet, 575 rows at
a time, and nothing on the page says it was guessed. **Its tie-breaking is also not deterministic**:
`max_by` on `[points, member_count]` keeps the first row the database happened to return, so one
list can be filed under either of two archetypes on two runs.

**(c) Containment selects the candidates, the Limitless deck name discriminates among them.** This
is what ships. `Decks::ArchetypeDetector`'s containment rule is kept exactly as it is — it answers
"which archetypes are entirely present in this list", which is the right question and a human chose
those members. The *ranking* changes: candidates are ordered by how many tokens of the Limitless
deck name appear in the archetype's name, and the weighted score only breaks a tie at equal
overlap. Measured over 96 lists:

| Outcome | Rows | Meaning |
|---|---|---|
| decided | 80 | one candidate leads on name overlap |
| the name says nothing | 9 | zero overlap with every candidate (`Basic Box`, `Tera Box`) |
| ambiguous | 4 | two candidates tie on overlap *and* score (`Dhelmise` between Banette and Sinistcha) |
| no candidate | 3 | containment found nothing (`Marnie's Grimmsnarl`) |

It fixes Slowking, N's Zoroark, Grimmsnarl Froslass and Clefairy Ogerpon. **One of the 80 "decided"
is still wrong** (`Alakazam Dudunsparce` → *Toucannon / Dudunsparce*, equal overlap, higher score).
So the rule is a good proposer and a bad decider, which is why it only ever proposes.

### The mapping is confirmed by a human, and it is keyed on the deck reference

**A resolution is per Limitless deck, not per row.** 575 rows carry 45 distinct decks, so the admin
arbitrates 45 lines. The key is the deck's own reference — the `/decks/<id>` href, with its
`?variant=N` when it has one — and **not** the display name. Measured on this event the two are a
bijection (45 names ↔ 45 references, no name under two references and no reference under two
names), so nothing is lost; but Limitless renames a deck as a metagame settles, and eight of the
references here are variants of a shared base id:

```
284    → Dragapult            326    → Lillie's Clefairy
284/3  → Dragapult Dusknoir   326/1  → Clefairy Ogerpon
284/9  → Dragapult Blaziken   329    → Marnie's Grimmsnarl
284/12 → Dragapult Dudunsparce 329/1 → Grimmsnarl Froslass
```

Keying on the base id alone would file four different decks as one. This is the same split issue #157
names from the other side, and this feature neither fixes nor worsens it: it records the reference
Limitless published and maps it, whatever that reference means.

The mapping is **persisted**, so the second event only ever asks about decks nobody has seen before.
A new table, `limitless_archetype_mappings`:

| Column | | |
|---|---|---|
| `limitless_deck_id` | integer, `NOT NULL` | from the href |
| `limitless_variant` | integer, nullable | `?variant=N`, nil for the base deck |
| `label` | string, `NOT NULL` | the display name as last seen, for the screen only |
| `archetype_id` | references, `NOT NULL` | what a row carrying this reference becomes |

UNIQUE on `(limitless_deck_id, limitless_variant)` — **partial-index territory**: SQLite treats
NULLs as distinct, the trap `Archetype`'s old `(primary_pokemon_id, secondary_pokemon_id)` index
fell into, so the base deck (`variant IS NULL`) needs its own partial UNIQUE index on
`limitless_deck_id WHERE limitless_variant IS NULL` beside the two-column one. Without it one base
deck takes as many mapping rows as it is confirmed times.

`label` is stored and never read as a key: it is what the confirmation screen prints beside the
select so the admin recognises the deck, and a rename on Limitless updates it without moving
anything.

### What the preview does, and what it costs

The preview reads the event's bulk decklists page (§4) — **one request, whatever the field size** —
takes one representative list per distinct deck reference, runs rule (c) over each, and renders one
line per reference: the label, the proposal with its reason (`decided` / `the name says nothing` /
`ambiguous` / `no candidate`), and a select the admin may override. A reference already in
`limitless_archetype_mappings` is shown as confirmed and is not proposed for again.

**A reference left unmapped is not a guess, it is a refusal.** Its rows are planned as `:blocked`
with a reason naming the deck, and the run reports them. That is the same treatment
`StandingsImportPlan` already gives a row whose division it cannot read, and it is the reason
nothing wrong enters the catalogue silently.

## 3. Find-or-create on the event

The key is `(name_normalized, date)` — already the catalogue's partial UNIQUE index and already what
`Tournament#name_and_date_are_unique` enforces. Measured: cartodex tournament 294 is named
"Regional Baltimore, MD" and dated 19 September 2026, byte-identical to the Limitless heading, so
the existing key finds it with no screen of its own. `Tournaments::StandingsImporter`'s
`find_or_create_tournament` already implements `find_by || create!` with the two rescues
(`RecordNotUnique` **and** `RecordInvalid`, because the non-atomic validation fires first) and
`EventPlan#similar_tournaments` already surfaces near-misses in the preview.

**On a found event, only nil columns are filled.** An event is wiki-governed: its creator or any
member may have corrected the tier, the format or a field size, and a re-import that reasserted
Limitless's values would revert that correction with no trace. Two of those columns are worse than
merely rude to overwrite — lowering a division's field size below a placement already recorded makes
existing standings invalid, which `Tournaments::StandingsController#unclaim` already has to work
around. So: `tier`, `format`, `other_format_name`, `standard_pool_id` and the four participant
counts are written when they are nil and left alone otherwise, and the preview says which ones it
would fill.

## 4. Volume — the event publishes its lists in bulk, and that is the whole design

The obvious shape is the one both existing sources have: one request per row to
`/decks/list/<id>`. Measured, that is **575 requests at a median 0.82 s, about 12.7 minutes** of
wall clock at the importer's 0.5 s pause — and it would have put 45 of those requests (37 s) inside
the preview's web request, which is what first made the mapping screen look unaffordable.

**It is not necessary.** `/tournaments/577/decklists` is one page carrying **all 559 Masters lists**,
in exactly the `[data-text-decklist] .decklist-card` markup `Tournaments::LimitlessDecklist` already
parses, and the division goes in the path before it: `/tournaments/577/SR/decklists` answers 200
with its 8. So a whole event costs **six requests**, not 575:

| | |
|---|---|
| Masters decklists page | 22.1 MB, 559 lists, 14186 card entries |
| `Nokogiri::HTML` parse | **0.30 s** |
| Walking all 559 lists | **0.28 s** |
| Peak RSS | 50 MB → 246 MB |

Each list block names its row, **in its toggle text and not in its attributes**: the toggle reads
`1st Dylan Kasturi`, and that ordinal is the results page's `data-rank`. `data-target="decklist-N"`
and `data-id="N"` look like the same number and are not — they are the block's index among the
*published* lists. On 577 the two agree everywhere, because all 559 rows published; on Cape Town,
which publishes 6 lists for 10 rows, the third block is `decklist-3` and its toggle reads
`6th Kevin Krueger`. Keyed on the attribute, one player's 60 is filed under another player's row.
The join is therefore on the stated rank, and it tolerates a missing block.

Three consequences, all of them the reason this is worth the 246 MB:

- **The preview's proposal is free.** One fetch yields every list, so proposing an archetype for all
  45 references costs one request rather than 45. The 37 s objection disappears.
- **The rule that turns markup into PTCG text stays spelled once.** `Tournaments::LimitlessDecklist`
  grows a class method taking a node set; both the per-URL path and the bulk path call it. Two
  copies of that rule is exactly the failure `Decks::Fetcher::SET_CODE_RE` exists to prevent.
- **The five-consecutive-failure abort becomes moot for this source.** A transport failure now
  happens once, before any row is written, instead of 575 times in the middle of a run.

The card-page traffic that dominates the existing sources is close to nil here too: **0 of 1405
distinct printing references on this event are missing from the development database.**

`StandingsImportPlan::DEFAULT_MAX_ROWS` is 300 and must still rise for a single event to be
importable at all. It is raised for this source only: the cap exists to stop an archetype-history
run walking 176 events, and one event is a bounded thing the admin has seen the size of in the
preview.

Two consequences are accepted rather than solved:

- **575 ownerless shared decks per event**, all listed on `/decks/shared`. This is the same effect
  the online source already has (one per imported row) and is named as out of scope there. It gets
  worse by an order of magnitude here. Not addressed in this lot.
- **The sheet is complete for the divisions published**, unlike an archetype-history import, which
  is a partial sheet nothing marks as partial. This source is the first that could honestly claim
  completeness; it does not claim it, because the Masters page publishes 559 of a 3122-player field
  (a day-2 cut) and "complete" would be a second lie.

## 5. What is deliberately out

- W-L-T and per-row attendance — not published on this page.
- `data-country` — no column, and no screen asks for one.
- Variant semantics (issue #157) — the reference is recorded and mapped, not interpreted.
- De-duplication (`player_slug` / `list_digest`) — that pre-pass exists because a *leaderboard* is
  one player's best finishes. An event's sheet is a field: two rows sharing a 60 are two people who
  both played it, exactly the case the paper source's NULL key already protects. `deduplicate:`
  stays false.
- Anything that would let this run from outside `/admin`.
