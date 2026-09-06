# Card labels: what a card *is*, and what it *does* (issues #155 and #154)

`Archetypes::CardStats` groups a deck report by what the database knows a card **is** —
`card_type` plus the scraped `subtype`. Two tickets ask for the other half:

- **#155** — group cards by what they **do** (Gust, Switch, Recovery, Draw), the way the reference
  deck reports this feature was modelled on do.
- **#154** — record the one thing a card *is* that nothing in the database says: whether it is an
  **ACE SPEC**.

They are specified together because they are the same store. Answered separately, #154 becomes a
boolean on `cards` and #155 becomes a label table, and the two do the same job with two write
paths, two admin surfaces and two things to migrate the day a third label matters.

Everything below was measured on the production dump (which is the development database, 107
standings / 4723 cards) or against the live source on 2026-09-05. The measurements are named where
they decide something.

---

## What the sources actually hold

### The catalogue already carries the text a role can be read from

- **51** distinct Trainer/Energy fingerprints cover everything played across the 107 recorded
  standings; **43** Pokémon fingerprints do the same, for 94 played cards in all. The whole
  catalogue holds **400** Trainer/Energy fingerprints over 795 rows. (#155 measured 49 before the
  online import of #153 landed; the shape is unchanged.)
- `cards.effect` is populated on **745 of those 795** rows.
- `attacks` and `abilities` both carry `name` and `effect`. **255** cards have an attack whose
  effect searches the deck, **100** an ability whose effect mentions drawing. This is what makes a
  *Pokémon's* mechanic readable without scraping anything new — the "Call for Family" case, where
  a Basic that searches out two Basics is doing the job of a search Item.
- **0** cards carry a NULL fingerprint today.

### Rules can propose and cannot decide

Six naive regexes over that text (gust / switch / recovery / draw / search / disruption) label
about **30 of the 51** played Trainer/Energy fingerprints. They miss exactly the cards a player
names first — **Iono, Judge, Professor Turo's Scenario, Pokégear 3.0** — and they hand
*Telepathic Psychic Energy* a `search` role it does not deserve. Coverage is not the problem;
the problem is that the errors are invisible on the rendered page. So rules suggest and a human
decides, and the store is built around that asymmetry rather than around a coverage number.

### `is:` is a family, and Limitless's own documentation of it is incomplete

`limitlesstcg.com/cards/syntax` documents `is:` with `v, gx, ex, prism-star (prism),
ace-spec (ace), radiant` plus six gameplay labels (`fusion-strike`, `single-strike`,
`rapid-strike`, `tag-team`, `ultra-beast`, `team-plasma`).

Measured against the live search, three tokens the page does **not** document answer perfectly:

| query | printing links on page 1 |
|---|---|
| `is:ace` | 46 (and the page prints "46 cards") |
| `is:ancient` | 50 |
| `is:future` | 50 |
| `is:tera` | 50 |
| `is:radiant` | 16 |
| `is:prism` | 27 |

This is the second time this feature area has found the only written description of a source to be
wrong (`tmp/limitless_scraper.py` was wrong on `data-place` and on decklist line text). It is also
the argument for the type vocabulary being **data**: Ancient and Future arrived mid-block in
Scarlet & Violet, ACE SPEC was revived from Black & White in the middle of the same block, and
Fusion Strike arrived late in Sword & Shield. A closed list in code is a deploy per set.

**One request reads a whole label.** The result page carries a `show` control whose `all` value
returns every match at once, and the `.search-summary` block states the count in plain text
(`46 cards found where …`). Measured: `is:ace` 46 links for an announced 46 in 25 KB, `is:tera`
151 for 151 in 50 KB, and the largest plausible label, `is:ex`, 986 for 986 in 234 KB — a quarter
of the 1.1 MB standings page `HttpFetcher` already reads inside its 30-second read timeout. So
there is no pagination to write, no page cap to tune, and the announced total is a real integrity
check rather than a stopping condition: a run that read 46 of 46 knows it is complete.

The links live in `.card-search-grid` as `<a href="/cards/<SET>/<NUM>">`, one per printing.

`cards.set_name` holds the set **code** (`PRE`, `TEF`), so the `/cards/<SET>/<NUM>` links the
search returns resolve with `Card.find_by(set_name:, set_number:)` — the same pair
`Cards::Fetcher` already looks a printing up by.

### Nothing else can produce the ACE SPEC flag

Re-verified from #154 and unchanged: all 18 ACE SPEC printings in the catalogue carry `rarity`
`"Ultra"`, and so do 93 ordinary Trainers; the string "ACE SPEC" appears in `effect` on 0 of the
4720 cards the catalogue held when #154 measured it; and the individual Limitless card page for
Prime Catcher renders "Trainer - Item" without the string anywhere, so extending
`Cards::Fetcher`'s parse of that page recovers nothing.

---

## The decisions

### 1. One store, two families, two governances

A single vocabulary table, `card_labels`, holding both families:

- **`role`** — what the card *does*: `draw`, `search`, `gust`, `switch`, `recovery`,
  `disruption`, `energy_acceleration`. The list itself is the constant `CardLabel::ROLES` — the
  one thing both the seed and the suggestion rules read, so the two cannot drift — and
  `db/seeds/card_labels.rb` walks it, **skipping any slug that already exists** — the
  `db/seeds/standard_pools.rb` pattern, "a bootstrap, not the source of truth", so that a
  `db:seed` on every boot never reverts an admin's correction.
  `Admin::CardLabelsController` refuses `create` and `destroy` on this family.
- **`type`** — what the card *is*, beyond `card_type`/`subtype`: `ace-spec` at seed time, and
  whatever else an admin adds. Full CRUD, and each row carries the `is:` token it is imported by.

The asymmetry is not taste. **A role slug is referenced by code** — its suggestion rule lives in
`CardLabels::RoleSuggester` — so an admin-invented role would be a label no rule can ever propose.
**A type slug is referenced by nothing but its own query**, so a new one is a row plus a run.

### 2. Assignments are keyed on the fingerprint, with the printing kept beside it

`card_label_assignments` carries `fingerprint` (the identity — "same card, any printing", the key
`CardStats` already groups on) **and** `card_id` (the printing the decision was made from,
nullable, `dependent: :nullify`). That is the `primary_card_id` / `primary_fingerprint` pair
`Archetype` already uses, for the same reason: the fingerprint is what the report joins on, and
the card id is what makes a fingerprint drift — which a `force: true` rescrape can cause —
repairable out of band instead of silent.

`bin/rails card_labels:resync_fingerprints` is that repair, and it **reports rather than writes**
where the answer is ambiguous, exactly like `Archetypes::FingerprintSync`. A card with no
fingerprint cannot be labelled at all: it stays visible in the report under its own id
(`CardStats::GROUPING_KEY`) and unlabelled, which is the honest outcome — never folded into a
neighbour.

### 3. Provenance decides who may overwrite whom

`source` is one of `imported` / `suggested` / `curated`, plus a `rejected` boolean.

- A **re-run of the suggester** rewrites its own `suggested` rows and touches nothing else. A pair
  that already carries a `curated` row is not even examined.
- A **human decision is a tombstone.** Ticking a role writes `curated` present; unticking writes
  `curated` rejected. There is no silent deletion, so "no, Iono is not Gust" survives every
  re-run, and "not decided yet" reads as exactly what it is: no `curated` row.
- The **import writes `imported` rows only**, and a curated decision outranks it.

The report reads `rejected = false`.

### 4. The import never deletes, and never scrapes a card

A re-run adds what is missing and **reports** the assignments the source no longer lists instead
of removing them. A page truncated by a transport failure can therefore not depopulate a label —
the same arbitration `FingerprintSync` makes when it declines to write.

A printing Limitless lists and the database does not hold is **counted in the receipt, not
created**. Acquiring cards is `CardSets::Importer`'s job, and since #121 a known printing is never
re-scraped. Because the key is the fingerprint, a **new printing of an already-labelled card
inherits its labels with nothing re-run**; only a card with a wholly new name needs another pass.

### 5. A role is a property of the card, and "attacker" is not a role

Roles are **game mechanics**, uniformly across card types: Fezandipiti ex is `draw` even in a deck
that attacks with it, and a Basic whose attack fetches two Basics is `search`. Every Pokémon is a
potential attacker, so "attacker" says nothing and is not in the vocabulary.

This is what keeps the table finite — 400 Trainer/Energy plus the Pokémon that carry a mechanic —
and keeps it from becoming per-archetype curation, which #155 exists to avoid. The known cost is
recorded rather than hidden: a role that is true of the card can be beside the point for one
particular deck. There is no per-archetype override, and adding one later is data plus a second
store, not a migration of this one.

### 6. The report gets a mode, not a second report

`Archetypes::CardStats.call(standings:, grouping: :type)` gains that keyword. `Entry`, `NameGroup`,
`fixed_core` and every percentage are computed identically in both modes; only the grouping of
entries into sections changes. That is what makes the two views incapable of telling two stories
about one sample — "N cards accounting for M copies are played by every list" is the same sentence
on both.

The control is **two links in the card report's own header**, carrying `?group=type|role` and
re-emitting `?pool[]=`. It cannot live in `Archetypes::SampleSelector`, which is dropped entirely
when `selectable?` is false. An unknown `group` value falls back to `type`, the way `#index` and
`#show` clamp an out-of-range `?page=` rather than raising or lying.

### 7. What the role mode has to say out loud

- **The sections do not add up to the list.** Iono is under `draw` and under `disruption`, Prime
  Catcher under `gust` and under `switch` — the overlap is half the vocabulary, not a corner case.
  One sentence at the top of the report in role mode, in the register of the one that already
  stops a reader taking Hoothoot's sub-rows for a decomposition.
- **A card with no role is not silent.** It falls into a final "No role recorded" section, rendered
  and counted — the arbitration `CATEGORIES`' `other` bucket already makes. On today's data that
  section is large (most of the 43 played Pokémon carry no mechanic), and that is the point: it
  shows the curation debt instead of hiding it.
- The rejected alternative, recorded because it reads better and is worse: letting unlabelled
  cards fall back to their **type** category in role mode. A reader then cannot tell "this card
  has no role" from "this card has not been curated yet", and the page starts asserting a
  classification it does not hold.

### 8. A type label annotates a row and never opens a section

ACE SPEC renders as a badge on the name line, beside the `fixed` flag that already lives in
`.archetype-card-name`, in **both** modes. It therefore takes no card out of "Item" and the
type-mode category counts stay a partition. The "one ACE SPEC per deck" rule is something the
reader knows; the page does not assert it, because nothing validates it.

### 9. For a Trainer or Energy, the assignment key is a name, and that is accepted rather than fixed

`Card#compute_fingerprint` only builds the composite digest — name plus HP plus attacks plus
abilities — for a Pokémon; a Trainer or an Energy gets `SHA256(name)` alone. Assignments are keyed
on that same fingerprint (decision 2), so for the labels this feature actually imports — almost
entirely Trainers — the key a label is written on is not "same card", it is "same name". Two
catalogue rows sharing a Trainer name where only one deserves the label would be given one
assignment and one badge between them, and `card_labels:resync_fingerprints` cannot repair that:
it moves an assignment onto whatever fingerprint a card's *current* printing computes to, and for a
Trainer that computation is still the bare name — it recomputes the same collapsing digest, not a
finer one.

That is right for the case this feature actually has: **every printing of Prime Catcher is an ACE
SPEC**, so folding its reprints onto one row is the correct answer, the same folding `CardStats`
already relies on to avoid splitting a reprinted Pokémon into meaningless halves (decision 2's own
argument, one level up the same key). The converse — two *different* Trainer cards sharing one
name, where the label is true of one printing and false of the other — does not hold today, and
three measurements say so rather than an assumption:

- **0 of the 400** distinct Trainer/Energy fingerprints in the catalogue span cards with different
  effect text — every name collision on file is a straight reprint, not two different cards
  wearing one name.
- **0 of the 29** fingerprints the live `is:ace` import labels reach a card the source did not
  list — the import's own blast radius is exactly the cards Limitless named, not a name-sharing
  neighbour.
- The canonical worry case, **Master Ball** — an ordinary Item in older sets, an ACE SPEC in
  PAR/TEF — has exactly **one** printing in the catalogue today, TEF 153. There is no older Master
  Ball on file to mislabel.

What would change the answer: a set import bringing in an *older* printing of a name whose card
text changed — issue #111's Japanese sets are the likely door, since they are expected to add
printings the western catalogue does not already hold under set codes that stay globally unique.
The day that happens, a name collision with different effects becomes real, and this key stops
being an accepted trade-off and becomes a defect — at which point Trainer/Energy fingerprinting
needs its own finer key, not a fix inside this feature.

---

## Shape of the change

Two stages, one spec. The split is not cosmetic: stage 1 is mechanical and verifiable against 18
printings already in the database, and stage 2 is where the judgement is. The §9.6 lesson of
`tmp/handoff-2026-09-05-tickets-metagame-suite.md` — four agents, a fully green suite, two blockers
found only by an adversarial review — argues against one reviewable-in-name-only PR.

### Stage 1 — the store and the `type` family (closes #154)

**Migrations (additive):**

```
card_labels               slug (UNIQUE), name, family, position, description, source_query, timestamps
card_label_assignments    card_label_id (FK), fingerprint (NOT NULL), card_id (FK, nullable),
                          source, rejected (default false), timestamps
                          UNIQUE (card_label_id, fingerprint); index on fingerprint
```

**Models:** `CardLabel` (`FAMILIES`, validations, ordered scopes — `ROLES` arrives with stage 2,
since stage 1 seeds no role row) and `CardLabelAssignment` (`SOURCES`, refuses a blank
fingerprint).

**Services:**

- `CardLabels::LimitlessSearch` — fetches `/cards?q=<token>&show=all` through `HttpFetcher` in
  **one** request and returns the `(set_code, number)` pairs **and the total the page announces**.
  That total is an integrity check, the same gesture `Tournaments::OnlineDecklist` makes when it
  checks a column's heading subtotal before the 60: a run that read 47 of an announced 92 says so
  in the receipt instead of implying the source lost half its cards.
- `CardLabels::Importer` — resolves each pair with `Card.find_by(set_name:, set_number:)`, writes
  `imported` assignments on the fingerprint, counts the printings not held, and reports (never
  deletes) the ones the source no longer lists.
- `CardLabels::ImportJob` — enqueued with **ids, not records**: the `Tournaments::StandingListImportJob`
  lesson, where a record deleted in flight raises `ActiveJob::DeserializationError` *before*
  `#perform` is entered, somewhere the method's own `rescue` cannot see it.

**Admin:** `Admin::CardLabelsController` (index/new/create/edit/update/destroy, the last two
refused on the `role` family) plus an `import` member action. The receipt is an `Import` of a new
kind, `card_labels`, which means the checklist that #153 had to discover is applied deliberately:
`Import::KINDS`, `Admin::ImportsController#retry` (an allowlist of `deck`/`card_set`, so this kind
is refused — there is nothing to replay but a fresh run), `#undo` (gated on the literal
`"limitless_standings"`, so this kind is not undoable, which is correct: a re-run writes exactly
the same rows), and both places the admin imports view branches on a kind.

**Report:** `CardStats` loads the assignments for the fingerprints it is reporting on — **one**
query — and `Entry` carries its labels. `Archetypes::NameGroupRow` renders the type badges.
`/archetypes/:id` goes from 16 queries to 17, flat, and the cost test says so.

**Seed:** `db/seeds/card_labels.rb`, wired into `db/seeds.rb`, so `bin/docker-entrypoint` plays it
**before the server accepts traffic** in the new image. Skip-if-exists on the slug. Stage 1 seeds
`ace-spec` alone; the same file grows the `CardLabel::ROLES` loop in stage 2.

### Stage 2 — the `role` family (closes #155)

- **Seed** the seven role rows.
- `CardLabels::RoleSuggester` — one versioned rule per slug, reading `cards.effect` plus
  `attacks.name/effect` and `abilities.name/effect`. Writes `suggested` rows, replaces only its
  own, never examines a pair carrying a `curated` decision. `bin/rails card_labels:suggest_roles`
  and an admin button.
- `Admin::CardRolesController` — the curation screen: one row per **fingerprint** (labelled with
  the representative printing), one checkbox per role, suggestions pre-ticked in a style distinct
  from decisions. Filters on card type, name, and **"played in a recorded list"**, which is what
  turns the 400 into 51 and makes the first pass an evening's work. Each row is its own
  auto-submitting form answering with a Turbo Stream that re-renders that row, so the state shown
  is the database's and not the browser's. A card with no fingerprint says so on its row instead
  of accepting a click that could not be written.
- **The report's role mode**, the `?group=` control, the overlap sentence and the
  "No role recorded" section.
- **Two texts become false and are corrected in the same change**: the `CLAUDE.md` paragraph
  asserting "no ACE SPEC category and no functional one", and the comment atop
  `Archetypes::CardStats#category_of` saying the same. (§9.2 of the handoff records two
  measured refusals that outlived their own truth; this is the same trap, seen coming.)

---

## Deliberately out

- **#156** — copies totals per category. The role mode *asks* its question ("what is a total worth
  when a card is counted twice") and deliberately does not answer it.
- **#157** — variants.
- **Per-archetype role overrides.** See decision 5.
- **Roles anywhere but `/archetypes/:id`** — not on the owner's deck page, not on a public deck,
  not in the JSON API, not in an MCP tool.
- **Type labels beyond `ace-spec` at seed time.** `radiant`, `tera`, `ancient`, `future` are rows an
  admin creates with their token the day they matter. That is the whole point of the family being
  data.
- **Creating cards the label search names and the catalogue lacks.** Counted, not fetched.
- **Validating "one ACE SPEC per deck"** anywhere, including on decklist import (which is #125's
  subject, not this one).

---

## Tests that must be written, because nothing existing goes red

Two habits from the handoff are steps of the plan here, not good intentions.

**"What would not go red?" (§9.4).** Before implementation, an adversarial pass measures what the
existing suite would fail to notice about the decisions above, and that list is written down. It
already has an obvious first entry: `CardStats::CATEGORIES` is a partition today and **no test
asserts that it is one**, so the role mode can break the type mode without a single red test.

**"What happens on the second import, six weeks later?" (§9.6).** The answer is built in above,
and the plan proves it with runs rather than arguments:

- re-running the label import after removing a card from the source leaves the assignment standing
  and names it in the receipt;
- re-running the suggester after a human rejection does not re-propose the pair;
- re-running either after a `force: true` rescrape that moved a fingerprint leaves the report
  unlabelled rather than mislabelled, and `card_labels:resync_fingerprints` repairs it.

Plus the house routine: every new test sabotage-verified (red, then restored green), the flat cost
pinned at 17 queries, the system suite at **both** viewports with a **geometry** assertion under
768px for the new badge and the mode control (§9.9 — a text assertion saw nothing there, because
the text rendered fine in the wrong place), and `rubocop` / `brakeman` / `importmap audit` on what
is written.
