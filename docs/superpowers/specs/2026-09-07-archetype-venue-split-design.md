# Splitting the card report's sample by venue (issue #160)

`/archetypes/:id` reports over a sample that blends online play with paper events, names the blend
in a sentence, and cannot cut it. This adds the cut.

Everything below was measured against a read-only snapshot of production taken on 2026-09-07 after
the bulk online import — **1238 standings, 293 events (287 of them online), 48 archetypes carrying
at least one list**. The measurements are named where they decide something, and two of them
reverse a conclusion an earlier comment on the issue reached honestly on smaller data.

---

## What is wrong today

`Archetypes::MetagameScope#buckets` groups on `tournaments.standard_pool_id` alone, so an online
weekly and a Regional anchored to the same pool land in the same bucket. Every percentage in the
card report below the selector then describes that mixture.

The issue was deferred once, with a condition: revisit when a mixed pool's paper half exceeds
`SMALL_SAMPLE`. It does now, on nine archetypes, and four of them hold cards whose inclusion
differs by fifty points or more between the two halves:

| archetype | paper | online | widest gap |
|---|---|---|---|
| Alakazam | 22 | 18 | Dunsparce **86 % → 6 %** |
| Teal Mask Ogerpon ex / Lillie's Clefairy ex | 32 | 18 | Telepathic Psychic Energy **0 % → 100 %** |
| Lillie's Clefairy ex | 9 | 19 | Grass Energy **78 % → 0 %** |
| Mega Excadrill ex | 14 | 19 | Tool Scrapper **57 % → 0 %** |

Alakazam's blended report prints `Dunsparce` at a figure near 50 %, which describes **neither**
half. That is the defect pool scoping exists to prevent, on a second axis — the argument
`2026-09-05-archetype-metagame-stats-design.md` makes for the first one, unchanged.

---

## The axis is venue, and tier is not

An earlier comment on the issue suggested tier might be the more interesting control — "what did
this deck look like at Worlds" is a question a reader actually has, and venue looked like a proxy
for it. On the data that arrived since, it is not, and the two are not the near-collinear pair that
comment assumed:

```
events   online=false   international 2 · worlds 2 · other 2      (6 events, 439 standings)
         online=true    other       287                           (287 events, 799 standings)
```

The paper half spans **three** tiers, and one of the three is `other` — exactly the value
`Tournaments::StandingsImportPlan` forces onto every online event. So `tier = "other"` is 799
online standings **plus** the 15 of *Japan Championships 2026*, a paper national championship. A
tier control does not separate what this issue asks to separate; it files a national with the
weeklies, and it splits the sample six ways where the measured problem is already that one side
falls under `SMALL_SAMPLE`.

Venue separates exactly. Tier remains a legitimate question and is a refinement **within** the
paper half — its own issue, not this one.

---

## The shape of the control

A second `<select>` beside the existing one, in the same form, labelled **Venue**, with options
**All / Paper / Online** each carrying its list count.

Three shapes were weighed. Folding the cross product into the existing pool selector removes the
empty-cell problem by construction but takes Dragapult ex to five to seven options with labels like
`TEF-PBL · online — 20 lists`. Rendering venue as tab links, the way `Archetypes::CardReport`
renders its grouping modes, is visually lighter — and wrong in kind: the grouping mode chooses how
to *display* a population, while venue chooses *which* population, which is what the sample block
above already decides. Venue belongs with the pool, in the same block, in the same idiom.

### The control is dropped unless both halves exist

`venue_selectable?` is true only when the selected sample holds standings from both venues. This is
the pool axis's own rule (`Result#selectable?`) applied unchanged: "All — 20 lists" beside
"Online — 20 lists" is two labels for one sample, which reads as a filter that does not filter.

Measured, that is the majority shape rather than a corner case — of the 59 (archetype, pool)
buckets, **24 are blended, 12 are paper-only and 23 are online-only**. The control is therefore
absent from 35 of them, exactly as the pool selector is absent from most archetypes.

### A half is offered from one standing, with no threshold of its own

A venue is an option whenever it holds standings; nothing hides a small half. A threshold at
`SMALL_SAMPLE` was considered and rejected on measurement: it would remove the control from 17 of
the 48 archetypes, **including Lillie's Clefairy ex**, whose paper half is 9 lists and which is one
of the four archetypes whose halves genuinely disagree. (That figure read 18 when this spec was
written; re-measured before implementation it is 17, under all four readings tried — lists `< 10`,
lists `<= 10`, standings `< 10`, and "any pool" rather than the default pool. The decision is
unchanged, since Lillie's Clefairy ex is among the 17 either way.) The threshold would silence a motivating
case. `small_sample?` already exists to say what a nine-list sample is worth, and it now fires on a
venue half as readily as on a pool.

"Holds standings" and not "holds lists", following the pool axis: `options` already renders a pool
with recorded placements and no typed decklist as `TEF-PBL — 0 lists`, and it must, because
`Archetypes::Performance` counts placements the card report cannot see.

---

## The scope

`Archetypes::MetagameScope` gains a second axis. It does not gain a sibling service, and the venue
filter is not applied in the controller — that class's opening comment promises it is "the only
place that answers which standings count", and the page's four printed "N lists" agree by
construction *because* one object computes them. A `where` in the controller would have the
selector print 118 while the report counted 98.

```ruby
MetagameScope.call(archetype:, pool_param: nil, venue_param: nil)
```

### One grouped query, and why the halves add up

`buckets` groups on `tournaments.standard_pool_id, tournaments.online` — a column added to a
`GROUP BY` on a scan that already runs, so it stays one query, and the row count at most doubles
(59 buckets, ≤118 rows, folded in Ruby).

`Bucket` becomes `(pool_id, online, standings, lists, last_on)`. The separate `online_lists` term
disappears: it is now the `lists` of the online row. A pool's option folds its two rows — sum of
`lists`, sum of `standings`, max of `last_on`.

That fold is only sound if a deck cannot be counted on both sides, since `lists` is a
`COUNT(DISTINCT deck_id)`. Measured on the snapshot: **0 decks carry standings under both venues**,
the fold matches the single grouped count on **59 buckets of 59**, and the same identity holds
across pools (1223 = 1223), which the existing `total.lists` already assumes. A test asserts the
identity rather than leaving it to the measurement.

### The clamp

A `(pool, venue)` cell can be empty, and the emptiness is not rare or random: **every pool other
than TEF-PBL holds zero online lists**, so 10 of the 38 cells belonging to multi-pool archetypes
with a blended pool are empty.

```
Dragapult ex     TEF-PBL(p98/o20)  SVI-BLK(p56/o0)
Raging Bolt      TEF-PBL(p3/o13)   TEF-CRI(p22/o0)  SVI-DRI(p68/o0)
Slowking         TEF-PBL(p18/o19)  no pool(p1/o0)
```

A venue naming an empty cell falls back to `:all`, the way an unknown `?pool=` already falls back
to the default pool "rather than on a 404 or an empty page". The fallback is recorded **in the
`Result`**, not merely applied to the relation: the select above the report and the report itself
must not disagree about which sample is showing.

### Pool labels do not move when a venue is chosen

`SVI-BLK — 56 lists` reads 56 whether or not Online is selected. The alternative — recounting each
pool within the current venue — is more literally true of a click and worse in practice: labels
shift under the reader between loads, and options appear reading `SVI-BLK — 0 lists`.

Stable labels are honest here **because of the clamp**, and only because of it: clicking
`SVI-BLK — 56 lists` under Online resets the venue and shows 56 lists. Symmetrically, venue options
count within the **currently selected pool**.

### `Result`

Gains `venue` (`:all` / `:paper` / `:online`), `venue_options` and `venue_selectable?`. The existing
predicates keep their meaning and need no clause: `online_lists_count` becomes `lists_count` under
Online and `0` under Paper, so the sentences that read it fall silent on their own, and
`fuller_sample_available?` compares against both option lists, so a 98-list paper half correctly
promises a fuller 118 one click away.

---

## The page

### The second select

`Archetypes::SampleSelector` renders both selects in the same `<form>`, Sample then Venue, submitted
by the same `card-filter` controller — so changing either re-emits the other, with no hidden state.
The hidden `group` field is unchanged. The block's guard becomes
`selectable? || venue_selectable? || small_sample? || online_lists?`.

**No new CSS**, and that is measured rather than assumed: `.deck-filters` is already
`display: flex; flex-wrap: wrap; gap: .5rem` and `.archetype-sample-label` is already the flex item
carrying a label and its select, so two of them sit side by side above the breakpoint and wrap below
it (2 × ≈195 px against a 390 px viewport). This is the trap `/archetypes`'s row note and
`.archetype-category-header` each paid for once; here the wrapper exists already. The system test
asserts the two bounding boxes at **both** sweep widths anyway — "it happens to be right today" and
"it is held" are different states, and nothing holds it today.

### The note under the selector is already false, on 23 pages

`online_note` prints its second sentence — *"The card report below counts online and paper lists
together"* — unconditionally, including when the sample is entirely online. Measured: **23 of the 48
archetypes** open on a sample with no paper list at all, so 23 production pages claim to count paper
lists that do not exist.

The rule becomes: the second sentence prints only when `online_lists_count < lists_count`. That
repairs the pre-existing defect and covers `venue=online` in the same line.

| venue | note |
|---|---|
| All, blended sample | "20 of these 118 lists come from an online tournament. The card report below counts online and paper lists together." |
| All, all-online sample | "Every list in this sample comes from an online tournament." — second sentence withheld |
| Online | as above |
| Paper | nothing: `online_lists_count` is 0, and the select already reads `Paper — 98 lists` |

### The mode links carry the venue

`CardReport#path_for` re-emits `venue` beside `pool` and `group`, read **off the scope and never off
`params`** — the discipline that component already documents for `pool`, and which matters more
here: the clamp is precisely the case where the two differ, and a link rebuilt from the parameter
would carry a dead venue into every copy of that URL.

---

## What follows for free, and what deliberately does not

**`Archetypes::Performance` splits in silence.** It reads `@scope.standings`, so a venue filter
reaches it without a line of its own. Its comment argues the events figure stays whole because
"every other number on the panel is over the same blended population" and notes that "that reasoning
stops holding the moment the population is selectable" — it stops holding here, and the resolution
is that the population itself narrows rather than that the panel grows a second number. Its two
online counters then read 0 or all, so its sentences withhold themselves.

**`/archetypes` does not change.** The issue body predates #153, which gave `Archetypes::IndexCounts`
its two online terms and the muted sentence under a blended row. The index names the blend; it has
no controls and gains none.

**No win rate**, unchanged and for the reason `Performance` already records: `wins`/`losses`/`ties`
are written on online rows and empty on paper ones, so a rate over either the blended sample or the
paper half misreports. Splitting the sample does not create the figure; it only makes the
temptation sharper.

---

## Cost

**17 queries, unchanged**, to be measured and not asserted. `buckets` stays one query;
`standings_scope` gains a `WHERE` on a table it already joins, and Rails deduplicates
`joins(:tournament)` against the joins `CardStats` and `Performance` make. The literal
`assert_equal 17` in `ArchetypesControllerTest` stays the guard and is extended to `?venue=paper`
and `?venue=online`.

**No migration.** `tournaments.online` and `tournaments.standard_pool_id` both exist, and the
composite `(online, date)` index arrived with the online import.

---

## Testing

Each of the following names the sabotage it must not survive, because a test that cannot go red has
shipped here twice.

| test | sabotage that must turn it red |
|---|---|
| paper + online = the pool's total | replace the fold with `COUNT(*)` on a pool row |
| pool labels do not move under a venue | recount pools within the selected venue |
| an empty cell clamps to `:all` **and the `Result` says so** | keep the parameter in the `Result` and filter only the relation — the select would read Online above a blended report |
| `venue_selectable?` is false with one venue | weaken it to `venue_options.size > 1`, which counts "All" and is therefore always ≥ 2 |
| the note withholds its second sentence at 100 % online | restore the unconditional sentence — this test **fails on `master` before any of this is written**, which is what proves it measures something |
| the mode links carry the *effective* venue | build them from `params[:venue]` |
| a venue half under the threshold sets `small_sample?` | a Crustle-shaped fixture, paper 8 / online 20 |
| a malformed `?venue[]=junk` does not 500 | drop the `to_s`, as `pool_param` documents |

Two system tests, at **both** sweep widths: choosing Online changes the report's denominator and its
percentages; and the two labels are adjacent above 768 px and stacked below it, asserted on bounding
boxes rather than on a class, since the existing `flex-wrap` is what does the work.

`Styleguide::PageView`'s `sg_metagame_scope` stub gains the venue fields and renders the two-select
state, which is the state that cannot otherwise be seen.

---

## Out of scope

- **A tier control**, for the reason measured above. "What did this deck look like at Worlds" is a
  refinement within the paper half and is its own issue.
- **Any win rate.**
- **`/archetypes`**, which already names the blend and offers no controls.
- **Re-publishing Limitless's own `Count / Share / Score / Win %`.**
- **A venue axis on anything but this page** — not on a deck page, not in the JSON API, not in an
  MCP tool.
