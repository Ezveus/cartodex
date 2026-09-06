# Copies per category on the archetype card report (issue #156)

The report's section headings say how many distinct cards a category holds. They do not say how
many *copies* of it a list plays. `Switch (2-3)` in the reference reports means "every list plays
between 2 and 3 cards of this category in total", and that number is not derivable from the
per-card figures already computed.

## Why no design spec

No table, no column, no query, no external source, no new public surface — the page is already
public to members and the sections already render. What outlives the diff is three decisions, and
they are recorded in the service's own comments and in `CLAUDE.md` rather than in
`docs/superpowers/specs/`: a later reader undoing one of them is editing the method the comment
sits on.

## The measurements this is built on

Taken on the dev database, which is the production dump, reproducing the page's own sample through
`Archetypes::MetagameScope` and `Archetypes::CardStats`.

**The naive interval is not merely wider than the true one — its lower bound frequently exceeds
the true maximum**, because a sum of per-card minima counts cards no single list plays together:

| Sample | Category | Σ per-card min … Σ per-card max | true per-list min…max |
|---|---|---|---|
| TEF-CRI (22 lists) | Item | **24–28** | 11–17 |
| TEF-CRI | Pokémon | 24–34 | 16–21 |
| SVI-DRI (68 lists) | Pokémon | 25–34 | 19–23 |
| All formats (106) | Pokémon | **39–57** | 16–23 |
| All formats | Supporter | 18–30 | 7–14 |

**A list playing none of a category is not hypothetical.** In type mode two categories reach zero
on the production data, and one of them is nearly always zero:

| Sample | Tool: lists playing 0 | Stadium: lists playing 0 |
|---|---|---|
| TEF-CRI (22) | **21** | 1 |
| SVI-DRI (68) | **56** | 0 |
| All formats (106) | **93** | 1 |

Every type category that appears at all is played by 100 % of lists in every bucket; Special
Energy opens no section for this archetype in any of them.

**In role mode the sections overshoot 60 by +1 to +8 copies** — mean +1.19 in the default pool,
+1.77 in TEF-CRI, +6.56 in the fullest *pool* (SVI-DRI) and +4.75 over the blended all-formats
sample — driven by 3–7 dual-role cards per sample; no card in the catalogue carries three roles.
The role histogram over the all-formats sample is `{0 => 37, 1 => 32, 2 => 7}`. Role mode has zeros
too: Switch is 0 in 5 of 16 lists in the default pool, and 22 of 106 blended.

**These role figures are not reproducible against the dev database as it stands.** The dump holds
29 assignments, all `type`/`ace-spec`, and **zero** role assignments — `CardLabels::RoleSuggester`
has never been run in production. Every role number above comes from running it (`created=714`,
`fingerprints_examined=3023`, matching `CLAUDE.md`) against a *copy* of the dump. Re-check them
without that step and the report reads one 60-copy "No role recorded" section per list.

**Even in type mode the section ranges do not add up to 60.** TEF-PBL reads Pokémon 17–20,
Supporter 9–14, Item 11–15, Stadium 3–4, Basic Energy 13–16: minima sum to 53 and maxima to 69,
while every list plays exactly 60. This is the same shape as the Hoothoot sub-rows the report
already refuses to let a reader add up, and it is what the page has to say out loud.

## The three decisions

### 1. Zeros are counted, deliberately unlike `Entry`

`Entry#min_copies` is the range **when played** — a list that does not play the card contributes
nothing to it — and that is right there, because the row prints its inclusion percentage right
beside the range. A section heading carries no such percentage. `Tool — 1 copy` over a sample where
21 lists of 22 play no Tool at all is true under the entry's rule and a lie as a description of the
sample, so the category range runs over **every list in the sample** and reads `0-1`.

This is the decision a later reader is most likely to "fix" for consistency with `Entry`. The
comment on the method says why it is not one.

### 2. Both grouping modes get the figure

The sections in role mode do not partition the list, so their copies add past 60 — measured at
+1 to +8. Each section's own total is nonetheless a true statement about that section, the page
already tells the reader in words that role sections overlap, and the reference reports print this
figure for functional groups first. Withholding it in role mode would withhold the more useful
half.

### 3. The ranges are per-list ranges and the page says they do not add up

One sentence under the summary, in both modes, in the register of the printing note and the
overlap note. Suppressed at one list — because there is no *range* to disclaim there, every
section printing an exact number, and **not** because the sections then sum to the list: in role
mode they still do not, a single list carrying one dual-role card already summing to 61. The
overlap note is what covers that case and it renders at one list too.

## The shape of the change

### `Archetypes::CardStats`

- `deck_ids` — memoise `@standings.distinct.pluck(:deck_id)`, and make `lists_count` its `size`.
  **This replaces the existing `count(:deck_id)` query rather than adding one** — measured, both
  forms are one statement and `CardStats` stays at 5 queries, `/archetypes/:id` at 17. It is what
  gives the aggregate the full list universe, including the lists holding none of a category.

  **It also turns the constructor's `where.not(deck_id: nil)` from a documented no-op into a
  load-bearing filter, and two comments must be corrected in the same commit.** `COUNT(DISTINCT
  deck_id)` drops NULLs; `pluck` returns a `nil` element that `.size` counts. Measured on a dump
  with one null-deck standing injected: `count` 106, `pluck.size` 107. Both the comment in
  `CardStats#initialize` and the one at `test/services/archetypes/card_stats_test.rb:30-34`
  currently tell a reader that deleting that line leaves every test green — true of `count`, false
  of `pluck`. A comment that instructs a future reader to break the code is the same defect as a
  test that guards nothing.
- `CategoryGroup` gains **one** member, `copies_per_list`, and derives `min_copies`,
  `max_copies`, `modes`, `single_quantity?` and `tied_mode?` from it — the names `Entry` already
  uses, so one text helper serves both. One member and not three aggregates, because three
  independent members with no default reproduce the `Entry#labels` trap in its *silent* variant:
  `nil == nil` makes `single_quantity?` true, `min_copies.to_s` is `""`, and the heading renders
  `" copies"` with nothing raised. `copies_per_list` defaults to `[]` through the same hand-written
  `initialize` `Entry` carries, and `copies_known?` is what the component asks — an absence that is
  deliberate for a caller rendering a section standing alone, and cannot be produced by the fold.
- `modes_of` becomes `CardStats.modes_of`, one definition called by `entry_for` and by
  `CategoryGroup#modes`; two spellings of "every value that ties for most frequent" would drift.
- One private `copies_by_list(section_entries)` folding `rows_by_key` — no new query, and O(the
  section's own rows) rather than O(rows × sections), because it walks the entries' rows rather
  than filtering every row per section.
- `type_categories` and `role_categories` both build their groups through one
  `category_group_for(key, label, entries)`, so the two modes cannot compute the figure
  differently.

### Views

- `Archetypes::CopiesText` — a module holding `copies_text` / `copies_range` / `copies_noun` /
  `mode_text`, extracted verbatim from `Archetypes::NameGroupRow` and included by it and by
  `Archetypes::CategorySection`. It takes anything answering `min_copies`/`max_copies`/`modes`/
  `single_quantity?`/`tied_mode?`, which is `Entry` and `CategoryGroup`.
- `Archetypes::CategorySection` — the heading's card count and the new copies figure go inside one
  wrapper `div.archetype-category-meta`. `.archetype-category-header` is
  `display:flex; justify-content:space-between`, so a bare third child would be spread across the
  row instead of grouping with the count. **This is the `/archetypes` index lesson repeated on a
  different flex container and it is verified by geometry under 768px, not by text.**
- `Archetypes::CardReport` — the range note, both modes, suppressed at one list.
- `application.css` — `.archetype-category-meta`, `.archetype-category-copies`,
  `.archetype-range-note`.

### Callers to update

`CategoryGroup` is built by hand in `test/components/archetypes/card_report_test.rb` and
`test/components/archetypes/name_group_row_test.rb`. The styleguide builds `Entry` and `NameGroup`
but never `CategoryGroup`, so `Styleguide::PageView` needs no change — verify rather than assume.

## Tests — the "what would stay green" list

Produced by an adversarial pass over this plan, which measured what the existing suite notices.
Three of the fixtures the plan first proposed would have proved nothing, and are named here as
traps rather than deleted.

| # | What could be implemented wrong | Why today's suite stays green | The fixture that catches it |
|---|---|---|---|
| 1 | Range "when played" instead of over every list | Every fixture in `archetypes_controller_test` and `archetype_metagame_test` gives every list the same categories, so the two rules coincide; `.archetype-category-count` is asserted **nowhere** in the repo | One-card category, **three** lists, one holding it → `0-1`, `modes == [0]`. Three and not two: at two the tally is `{1=>1, 0=>1}` and the tie hides which rule produced it |
| 2 | Fold seeded from the decks appearing in `rows` rather than from `deck_ids` | A list with no `deck_cards` exists in `card_stats_test.rb:266` and nothing asserts copies about it | Two lists, one holding 60 Pokémon, one holding nothing → Pokémon reads `0-60` |
| 3 | Summing per-card min/max instead of folding per list | The tied-mode fixture at `card_stats_test.rb:68` **coincides** (both give 3–5) — the most likely fixture to reuse, and it proves nothing | Two cards in one category, `(4,1)` and `(1,4)` across two lists → `single_quantity?`, `"5 copies"`; the wrong answer is `"2-8 copies"` |
| 4 | Folding over `rows` wholesale rather than the section's own entries, in role mode | Nothing counts copies per role section | Iono 4 (draw+disruption) + Nest Ball 3 (search) → `draw` 4, `search` 3, never 7 |
| 5 | Going back to `DeckCard` instead of `rows_by_key`, re-splitting two printings of one card | `card_stats_test.rb:124` pins it at entry level only | Extend that fixture with a second card in the same category, assert the section total |
| 6 | A tie on a category resolved silently | — | Built on a fixture where per-card and per-list answers **differ**, unlike `:68` |
| 7 | `count` → `pluck` changing the sample | — | `card_stats_test.rb:257` "the four list counters agree" must stay green **unchanged** |
| 8 | A query added per section by the fold | — | The existing literal `assert_equal 17` in both modes. **Not** to be relaxed to `type == role`: measured, an N+1 per section read 17→18 on a one-section fixture and 17→25 in production while that equality stayed true |
| 9 | Pluralisation lost in the `CopiesText` extraction | `copies_noun`'s singular branch renders in `split_group_with_fixed_printing` and **no test asserts it** — the only `"1 copy"` in the file is `fixed_core`'s own | `assert_includes "1 copy"` and `assert_no_match(/1 copies/)` |
| 10 | `CategoryGroup` built without the new member rendering `" copies"` | Would not raise: `nil == nil` is `true`, so `single_quantity?` short-circuits every other member | Build one the way the two updated callers do; assert no `" copies"` fragment |
| 11 | The heading's wrapper omitted | Every assertion on `.archetype-category-header` targets the `h3`; there is no `category_section_test.rb` at all | Adjacency of `.archetype-category-count` and `.archetype-category-copies`, at **1400px as well as** below 768px — see the view section for why 390px alone can pass with the bug in place |
| 12 | The two `where.not(deck_id: nil)` comments left as they are | They are comments; nothing goes red, and they now instruct a reader to delete a load-bearing line | Not a test — a correction in the same commit |
