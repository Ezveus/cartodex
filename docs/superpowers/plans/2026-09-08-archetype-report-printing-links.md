# Naming and linking the printing in the archetype card report

`/archetypes/:id`'s card report prints a bare card name and links nothing. Two changes:

1. every card row names its printing — `Buddy-Buddy Poffin (TEF 144)`;
2. every card row links to the printing it names.

**No design spec.** This adds no table, no column, no external source, no public surface, and no
rule about what the data *means*. The three rules it does create are about this one component's
markup and belong in its own comments plus the paragraph in
`docs/architecture/archetype-metagame.md` that already governs this page — a spec file would be a
second place for them to drift from. Stated here on purpose rather than skipped in silence.

## Measured facts

| Fact | Where it came from |
|---|---|
| `Entry#card` is a full persisted `Card`, not a plucked row | `card_stats.rb:307-309`, `Card.where(id: representative_ids.values)` — no `select` |
| So the change costs **no query**; `/archetypes/:id` stays at 17 | the literal is pinned at `archetypes_controller_test.rb:378` and `:524` |
| `Card#printing_label` already produces exactly the requested form | `card.rb:78-80`, `"#{name} (#{set_name} #{set_number})"` |
| The split sub-rows already print it; the non-split name line prints `@group.name` | `name_group_row.rb:109` vs `:34` |
| The printing shown per fingerprint is already deterministic — most-played, lowest card id breaking the tie | `card_stats.rb:293-305` |
| Longest label in the dump: `"Technical Machine: Evolution (PAR 178)"` — 38 chars against 28 for the bare name | `bin/rails runner` over Dragapult ex, 174 lists / 126 entries |
| 53 split name groups over the 48 archetypes' all-formats samples — 36 distinct names, 30 archetypes, at most 4 printings (`Applin` and `Charcadet`) | a run over every archetype; **corrected** — this row first read "25", a number counted by eye off a `head -30`, which is the "report a figure you did not read out of a command" failure this pipeline names |
| 16 distinct card keys fold two printings a list actually played, so a *non-split* row can name one printing while its figures cover both | same run, and the domain review's own count agreed |
| `/cards/:id` is public, `/archetypes/:id` is member-only | `routes.rb:59` vs `:118` |
| `Card` has no `to_param`, so `card_path(card)` is `/cards/<id>` | grep over `app/models/` — only `Deck` defines one |

## Decisions

**1. A plain `a` whose href comes from `Rails.application.routes.url_helpers.card_path`, never
`link_to`.** `Archetypes::CardReport#path_for` already does exactly this and documents why:
`NameGroupRow` and `CategorySection` are unit-tested through a bare Phlex `.call`, where
`Phlex::Rails::Helpers::LinkTo` and `::Routes` delegate to a nil `view_context` and raise
`NoMethodError`. `Ui::ArchetypeBadge` writes its anchor by hand for the same reason.

**2. No `data-turbo-frame="_top"`.** `Ui::ArchetypeBadge` needs it because every call site
renders it inside a frame; these links are not frame-scoped, so `_top` would be cargo-culted.
*Corrected against the browser* — this decision was first justified as "`/archetypes/:id` renders
no `turbo_frame_tag` at all", which is false: the page carries one, `search_results` from the
layout's spotlight. It holds neither the report nor any card row (`closest("turbo-frame")` on an
anchor is null, measured), so the conclusion stands and the reason does not.

**3. A split name line gets neither a code nor a link; its sub-rows get both.** A split name
covers two or more genuinely different cards, so one printing's code on the name line would assert
about the group what is true of one member only. That is the rule the component already applies
twice — it withholds the `fixed` flag (`:44-47`) and the type labels (`:63-72`) from a split name
for exactly this reason — and the sub-rows *are* the card rows, so requirement 1 is satisfied
there by construction. `Applin` under four printings is the shape that makes this concrete.

**4. Whatever element carries the name text keeps `archetype-card-name-text`.**
`archetype_metagame_test.rb:153` measures that element's bounding box against the label badge's,
and that is the assertion proving `.archetype-card-label-line`'s wrapper works. The anchor replaces
the span on a non-split row and takes the class; a split row keeps the span. Exactly one element
per row carries it, as today.

**5. The sub-row anchors do *not* take `archetype-card-name-text`** — a second one in the row would
make that test's `find(".archetype-card-name-text")` ambiguous the day the labelled archetype's row
is a split one.

**6. Styling follows `.deck-compare-card-link`** (`application.css:1034-1044`): `color: inherit`,
`text-decoration: none`, underline on hover. `/decks/compare` is the app's existing table of linked
card names, and the report's own typography must not move — the name line is `font-weight: 600` and
the sub-rows are `400`/`--ink-700` via `.archetype-printing-row .archetype-card-name`, both of
which `inherit` preserves.

## Files

- `app/views/components/archetypes/name_group_row.rb` — the two render sites.
- `app/assets/stylesheets/application.css` — one rule pair, inside the archetype block, which
  overrides nothing (that block's preamble is explicit that only one selector there buys weight).
- `app/views/components/styleguide/page_view.rb` — `sg_entry` (`:450-456`) builds
  `Card.new(name:, set_name:, set_number:)` with **no id**, so `card_path` raises
  `ActionController::UrlGenerationError` and `/styleguide` 500s. `styleguide_controller_test.rb` is
  what catches it. Give the stub cards ids, as the same file already does at `:238-239`.
- `test/components/archetypes/name_group_row_test.rb` — its `entry` helper (`:225-231`) builds
  idless `Card.new` too, and its header comment (`:11`) asserts "nothing in this component tree
  uses a route helper". Both need correcting.
- `test/components/archetypes/card_report_test.rb:181`, `category_section_test.rb:56` — same idless
  `Card.new`, reached through `NameGroupRow`.
- `test/controllers/archetypes_controller_test.rb`, `test/system/archetype_metagame_test.rb`.
- `docs/architecture/archetype-metagame.md`, and `CLAUDE.md` only if a rule bites from outside.

## Tests to write

Each one is here because something today would stay green without it.

1. **Component, non-split row names the printing and links it** — assert the href is
   `/cards/<that card's id>` and the text is `Iono (PAL 185)`. Green today: nothing asserts a link
   anywhere in the report, and the name-line assertions in `name_group_row_test.rb` all match on
   substrings of the name.
2. **Component, a split row links every printing to its own card** — three sub-rows, three
   *different* ids. A test counting anchors, or asserting one href, stays green when all three
   point at the representative of the first entry.
3. **Component, a split name line carries no href and no set code** — the rule from decision 3.
   Nothing else would report it if a later edit "tidied" the two branches into one.
4. **Controller, the rendered page carries the link** — the component tests cannot see that the
   real, persisted card's id is what reaches the page.
5. **Controller, the cost is unchanged** — the existing `17` literals at `:378`/`:524` already do
   this; no new test, but they are the gate.
6. **System, at 390px a worst-case label does not push the card row past the panel or scroll the
   page sideways.** `ArchetypeReportModesNarrowTest` asserts `scrollWidth <= innerWidth` today but
   over `reported_archetype`, whose card names are fixture-short — so it would not notice the +10
   characters. The new test uses a name as long as production's worst
   (`Technical Machine: Evolution`) and measures the card row's own right edge against the panel's.
7. **System, the link actually navigates to the card page** — a request test sees a 200 for a page
   nobody can reach, and this is the one thing that proves the absent `_top` is right rather than
   merely absent: frame-scoped, the click would render Turbo's "Content missing".

## Sabotage list (phase 6)

For each new test, the mutation that must turn it red: drop the anchor; point every sub-row at
`@group.entries.first.card`; give the split name line `printing_label` and an href; drop
`archetype-card-name-text` from the anchor; revert `.archetype-card-link` to a bare anchor
(underline + link colour, which is a *visual* change no assertion above covers — expected to be
un-sabotageable, and to be recorded as such rather than annotated as covered).

---

## What the adversarial review of this plan changed

Eleven of the plan's claims were verified by running code (an `Entry` provably cannot carry an
unpersisted card at runtime — `entry_for` is `cards[…] or return nil` inside a `filter_map`;
`span`→`a` is layout-neutral because `.archetype-card-name-text` has no CSS rule and the app has no
global `a { }` layout rule; no ancestor anchor exists; `url_helpers.card_path` and the
view_context's agree because `relative_url_root` is nil). Six findings changed the work.

**A. A non-split row folds reprints too, so "it names its printing" needed the page to say which
one — and the page already says half of it.** `GROUPING_KEY` is the *printing-independent card
key*: measured on production, 81 card ids fold to 72 fingerprints. So a single-entry `NameGroup`
can cover a sample that played two printings, and the code shown is the most-played one. That is
**not** the case decision 3 refuses: a split name is two genuinely *different cards*, while a fold
is one card under two codes — which is exactly the distinction `Archetypes::MethodNote` already
draws ("reprints of one card fold together while two genuinely different cards sharing a name …
stay apart"). It is also the case the request settles explicitly: *"utilise n'importe quelle
combinaison correspondant au fingerprint — TEF 114 ou PRE 101 n'importe pas"*. So the code is a
label for the card, not a claim about the sample, and **`MethodNote` gains one clause saying so**.
No behaviour changes; the page stops implying something it does not mean.

**B. No controller or system test has ever rendered a printing sub-row.** `listed_standing_for`
(`archetypes_controller_test.rb:705`) gives every standing a uniquely-named card, and the system
helpers use one printing each — `archetype-printing-row` appears in `name_group_row_test.rb:80`
and in the CSS, nowhere else. So `NameGroupRow#printings` — where the sub-row anchors, decision 3
and decision 5 all live — is exercised by no request test at all. **New: a controller test over a
report holding a split name**, asserting each sub-row's own href.

**C. The three `17` literals are blind to an N+1 through an association, because the test cards
have no `card_set`.** A `belongs_to` with a NULL FK emits no query, so an implementation reaching
for `card.card_set.code` instead of `set_name` — the exact "improvement" a later reader would try
on a line that names a printing — costs nothing in test and one query per card in production.
**New: `listed_standing_for` gives each card its own `card_set`.** It renders nothing today, so the
count stays at 17 and the literal becomes genuinely defensive.

**D. Which printing is representative — now the target of every link — is pinned by nothing.**
`card_stats_test.rb:125` is the only test in the repo that builds two printings of one fingerprint,
and it asserts the entry's numbers, never which `card` it carries; `:328` builds two *different*
fingerprints, so the tie-break is never exercised. Flipping `[ lists, -card_id ]`
(`card_stats.rb:304`) would change the code and the href of every link on the page with the suite
fully green. **New: a service test pinning the representative** — most-played wins, lowest card id
breaks a tie.

**E. Decision 5 is not covered by the ambiguity of `find(".archetype-card-name-text")`.**
`labelled_archetype` builds one list and one printing per name, so `printings` never runs there and
a second element carrying the class would stay green until a fixture happened to split. **New:
`assert_equal 1, html.scan(/archetype-card-name-text/).size` on a split group.** (The converse —
*dropping* the class from the non-split anchor — is covered: `find` raises `ElementNotFound`.)

**F. Planned test #6 was vacuous and is dropped.** `.archetype-card-name` is `min-width: 0` with
`flex: 1 1 12rem`, no descendant sets `white-space: nowrap`, and a text flex item's min-content is
its longest word — `Evolution`, nine characters. So a longer label *wraps*; it cannot overflow, and
no mutation available to this change could turn an overflow assertion red. The 390px check is
therefore done **in the browser by hand with a worst-case label, and the measurement recorded**,
which is what phase 6 asks for anyway. What stays in the suite is the navigation test (#7), which
guards two things rather than one: that `assert_select`'s HTML4 parser cannot see a future nested
anchor (`archetype-metagame.md:200`), and that the absent `data-turbo-frame` is right rather than
merely absent.

**Also noted, not acted on:** `.deck-compare-card-link` carries `display: flex; align-items:
baseline; gap: 0.5rem` beside the two declarations being borrowed. Copying it whole would turn a
text flex *item* into a flex *container* and move geometry that only `archetype_metagame_test.rb:153`
could judge — so the new rule is three declarations and its comment says why. And
`name_group_row_test.rb:48`/`:68`/`:72` are adjacency regexes that break mechanically once the
sub-row text is wrapped in an `<a>`; they are rewritten in this commit and do not count as coverage
of anything here.
