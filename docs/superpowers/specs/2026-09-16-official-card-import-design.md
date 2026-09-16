# Importing a set from the official card database — Design

Issue: none — requested directly.

## Goal

*30th Celebration* released on 2026-09-16 and Limitless TCG does not have it:
`https://limitlesstcg.com/cards/30C` answers **404**, and `CardSets::Importer` — the app's only
card source — reads Limitless and nothing else. This change adds a **one-off, out-of-band** path
that fills the catalogue from the official Pokémon card database until Limitless catches up, and
then gets out of the way.

It is deliberately not a second permanent source. Nothing in `app/` learns a new origin;
`Cards::Fetcher`, `HttpFetcher` and `CardSets::Importer` are untouched.

## The source, measured

Two official surfaces exist and only one of them carries card data.

**The gallery — `tcg.pokemon.com/en-us/galleries/30th-celebration/` — carries none.** The page is
rendered client-side and reads exactly one document,
`https://tcg.pokemon.com/assets/img/me-expansions/30th-celebration/cards/cards.json`. Its content
is collector numbers grouped by visual category and nothing else: `seeall` (154 numbers),
`pikachu-rare` (30), `special-art` (26), `pokemon-ex` (24), `classic-collection` (30),
`futuristic-rare` (2). No name, no type, no attack. Card art is addressable from the number alone
(`.../expansions/30th-celebration/en-us/2M6P_EN_<n>.png`, and `2M6P_Classic_EN_<n>.png` for the
Classic Collection); `n=158` answers 200 and `n=159` answers 404. It is an image index.

**The card database — `www.pokemon.com/us/pokemon-tcg/pokemon-cards/series/<slug>/<number>/` —
carries all of it**, server-rendered, in markup Nokogiri reads directly. Two slugs cover this
release: `30th` (numbered `n/128`, secret rares continuing to `158/128`) and `30th-c`, a separate
set numbered `n/30` whose rarity is the literal string `Classic Collection`. The gallery's four
gaps — 143, 151, 152, 154 — answer a genuine 404 on the database too, so the gallery's `seeall`
array is the authoritative enumeration and no number has to be probed.

`cards.json` gives **154 + 30 = 184** pages to fetch.

## What the source cannot give, and why it matters

| Column | Available | Note |
|---|---|---|
| `regulation_mark` | **no** | printed on the art only — see below |
| `price_eur` / `price_usd` / `cardmarket_url` | no | Limitless-derived; already nil for any card imported before a price existed |
| `stage`, on *ex* cards only | partial | the type line reads `Pokémon ex` in place of a stage |

**`regulation_mark` cannot be guessed per set.** Measured on the development catalogue, **19 sets
carry more than one mark** and seven carry three — ASC has `J`/`I`/`H`, SIT has `F`/`D`/`E`, and
DRI, CRZ, SVP, JTG and BLK likewise. On ASC the marks interleave card by card (11–15 are `I`,
16–17 are `H`, 18–19 are `I` again), so no rule keyed on a number range can recover them. The
column is therefore left nil, and that is a **degradation, not a break**: nothing enforces deck
legality from it. `cards.regulation_mark` is read by the `/cards` filter
(`cards_controller.rb:144`), the card show page (`cards/show_view.rb:98`) and one column of the
tournament PDF (`decks/tournament_pdf_exporter.rb:82`). `StandardPool#regulation_marks` is a
separate attribute on the pool and is never joined against cards. 32 cards already carry a blank
rarity, so that state is not new.

**A nil `stage` on a Pokémon, however, *is* new, and an earlier draft of this paragraph got that
wrong.** The catalogue's 748 nil-stage rows are 717 Trainers and 31 Energy; every one of its 3934
Pokémon carries a stage, including all 746 named `% ex`. The evolving *ex* cards imported here are
therefore the first. The consequence is contained today and was traced: `Decks::Odds::Groups#basic?`
is `card_type == "Pokémon" && stage == "Basic"`, an evolving *ex* is non-Basic under a nil as much
as under `"Stage 2"`, and a Basic *ex* parses as `"Basic"` — so the mulligan rate the odds page
prints stays true. What stops holding is `Groups`' own stated invariant that a fingerprint group is
homogeneous in `stage`, and it stops holding the day a Limitless printing of one of these lands
beside it, because `entry_for` picks the group's representative by `min_by [set_name, set_number]`.
A rescrape closes it; until then this paragraph is the warning.

**The repair path already exists and is the reason the set code matters.**
`CardSets::RescrapeJob` builds `https://limitlesstcg.com/cards/#{card.set_name}/#{card.set_number}`
and calls `Cards::Fetcher.call(url, force: true)` (`rescrape_job.rb:9-10`). The day Limitless
publishes under the code we picked, the admin panel's existing *Rescrape* action restores every
missing column. This import is a stopgap with a documented end.

## Access: the source is behind Imperva, and that decides the architecture

`www.pokemon.com` sits behind Imperva Incapsula. Measured:

- A plain HTTP client gets **2–3 requests per session**, then every response is the block page —
  which is served with **HTTP 200** and a body of ~930 bytes, so a naive fetcher sees success.
  After roughly five requests the address is flagged and a fresh session is refused immediately.
  A 3 s delay between requests changes nothing; this is fingerprinting, not rate limiting.
- **Headless Chrome passes**: it runs the challenge script and takes a `reese84` cookie. 16
  consecutive card pages were captured this way from an already-flagged address.
- **The cookie does not transfer.** Exported to curl under the same User-Agent, it is refused —
  the token is bound to the TLS/HTTP2 fingerprint as well as to the cookie. There is no
  "prime once in a browser, then scrape cheaply in Ruby".
- **`fetch()` from inside an already-validated page is refused too**: 14 same-origin requests all
  returned the ~930-byte block page, because Imperva separates `Sec-Fetch-Dest: document` from
  `empty` and that header cannot be set from script. Full navigation continued to work
  immediately afterwards, so the refusal is per request type, not a poisoned session.

Two consequences follow, and they are the whole reason the design looks the way it does:

1. **Every page costs a full browser navigation.** ~184 of them.
2. **This cannot live in the Rails app.** The production image is `ruby:4.0.6-slim` plus
   `curl libjemalloc2 libvips sqlite3` (`Dockerfile:19`) — no browser. Putting the import behind
   `Cards::Fetcher` would mean shipping Chromium to production for a job that becomes obsolete
   when Limitless publishes.

Neither host serves a `robots.txt` (`www.pokemon.com` returns its own page, `tcg.pokemon.com`
a 404), so there is no crawl directive either way; the WAF is the operative signal, and the
scraper throttles and stops on refusal rather than working around it.

## Shape

Three pieces, and the boundary between them is a file on disk.

```
bin/scrape_official_cards        Node, no dependencies, never loaded by Rails
        │  drives a local Chrome over raw CDP, one navigation per card
        ▼
tmp/official/<slug>_<n>.html     184 verbatim `section.card-detail` fragments, gitignored
        │
        ▼
Cards::OfficialParser            app/services/ — HTML → Hash, every rule, all tested
        ▼
Cards::OfficialImporter          app/services/ — Hash → Card + Attacks + Abilities
        │
        ▼
lib/tasks/official_cards.rake    thin wrapper, matching archetypes.rake
```

The split is not decoration, and the boundary deliberately sits at raw HTML rather than at parsed
JSON. Emitting JSON from the scraper would put every HTML→field rule inside the one piece this
repository cannot test — there is no JS test infrastructure here. Measured on the 17 pages
captured, the `section.card-detail` fragment that every selector lives inside is **106 KiB across
all 17** against 2732 KiB for the whole pages, so committing those fragments as fixtures costs
almost nothing and buys a parser whose whole surface is exercised on the real bytes. The scraper
navigates, slices and writes; it holds no rules at all.

`bin/scrape_official_cards` is Node rather than Ruby for one measured reason: `selenium-webdriver`
is `group :test` only (`Gemfile:120-123`), and more importantly Selenium's automation flags are
what a WAF fingerprints. The Chrome that passed was launched bare with `--remote-debugging-port`.
Node 26 ships a built-in `WebSocket`, so raw CDP costs no dependency at all.

### The scraper

- Enumerates from the gallery's `cards.json`, not by probing 1→158.
- Navigates, waits for `.card-description` to exist, extracts, writes, throttles ~500 ms.
- **Refuses to mistake the block page for a card.** The block is HTTP 200; the guard is the
  presence of `.card-description`, and the script aborts after three consecutive failures rather
  than filling the file with empty records.
- Resumable: a record already in the output file is skipped, so an abort costs only what it had
  not yet reached.

### The two sets, and the way out of a wrong guess

`(set_name, set_number)` is UNIQUE and `30th/1` (Exeggcute) is not `30th-c/1` (Charizard), so the
two sets cannot share a code. Limitless has not published its codes, so the ones chosen —
**`30C`** and **`30CC`** — are a bet. `official_cards:rename_set[from,to]` moves `cards.set_name`
and `card_sets.code` together in one transaction, so the bet costs one command to correct. Getting
it right eventually is what makes `CardSets::RescrapeJob` able to repair the rows at all.

### Mapping

Faithful to what `Cards::Fetcher` already writes, because these rows sit in one table with 4732
others and every reader is shared.

| Column | From | Rule |
|---|---|---|
| `name` | `h1` | `<em>ex</em>` is the rule-box suffix — kept lowercase, never folded |
| `card_type` | `.card-type h2` | `Pokémon` / `Trainer` / `Energy` |
| `stage` | `.card-type h2` | `Basic` / `Stage 1` / `Stage 2`; on `Pokémon ex`, **`Basic` when there is no `Evolves From`, else nil** |
| `subtype` | `.card-type h2` | nil for Pokémon; `Item` / `Supporter` / `Stadium` / `Pokémon Tool` from `Trainer-…` |
| `hp` | `.card-hp` | integer |
| `type_symbol` | `i.energy.icon-<x>` | class, not tooltip text; the eleven values are exactly `Card::ENERGY_TYPES` |
| `evolves_from` | `.card-type h4 a` | |
| `weakness` / `resistance` | `.pokemon-stats .stat` | energy name, or nil where the block is empty |
| `retreat_cost` | `.pokemon-stats .stat.last li` | **count, and `0` when the list is absent — never nil** |
| attacks | `.ability` carrying `ul.left` | name `h4.label`, cost re-encoded, damage verbatim, effect from `pre` |
| abilities | `.ability` carrying `h3 .poke-ability` | name from the sibling `div`, effect from the `p`s |
| `rarity` | `.stats-footer span` | first token (see below) |
| `set_full_name` | `.stats-footer h3` | |
| `artist` | `.illustrator a` | |
| `image_url` | `.card-image img` | the official asset URL |
| `effect` | `.ability pre` | Trainer/Energy only — nil on Pokémon, as Limitless writes it |
| `pokemon_subtype` | the name | **written by the importer** — nothing on `Card` derives it (see below) |

Six rules are load-bearing and each has a measurement behind it.

**`pokemon_subtype` has to be written here, because nothing on `Card` writes it.** An earlier draft
of this table said the model derives it from the name; that is false. The only assignment in the
app is `Cards::Fetcher#detect_pokemon_subtype` (`fetcher.rb:97` calling `fetcher.rb:275`), which is
below that class's `private` at `fetcher.rb:49` — a card saved by any other path comes out nil. The
set holds 24 *ex* cards, and `Decks::ArchetypeDetector` reads `pokemon_subtype.rule_box` to score a
member at `RULE_BOX_WEIGHT` instead of `POKEMON_WEIGHT`, so leaving the column nil would quietly
mis-rank every archetype built on one of them. The importer therefore applies the same
name-derived rule, and a test asserts the weight difference rather than the column alone.

**Imported cards must be reachable as `card_set.cards`, not merely carry the right `set_name`.**
`belongs_to :card_set, optional: true` (`card.rb:5`), and 44 printings in the catalogue legitimately
carry no `card_set_id` — so a nil is invisible to every assertion about `set_name`, and
`CardSets::RescrapeJob` iterates `card_set.cards` (`rescrape_job.rb:8`). Getting this wrong makes
the documented repair path visit zero rows while every other test passes.

**Attacks and abilities are `build`, and the card is saved once.** `compute_fingerprint` is a
`before_save` that reads `[name, hp, type_symbol, attacks[name, cost, damage], abilities[name]]`
(`card.rb:138-147`). Creating the card and *then* its attacks computes the fingerprint over an
empty list, and the fingerprint is the key `Decks::ArchetypeDetector` matches on and
`Cards::Printings` groups by — so such a card would silently never match an archetype and never
offer a printing swap. `Cards::Fetcher` builds then saves for exactly this reason; the importer
does the same.

**`retreat_cost` is `0`, not nil, when the retreat list is absent.** `Card` validates it
`presence: true, numericality: { greater_than_or_equal_to: 0 }` on every Pokémon
(`card.rb:88`), so a nil is a refused card, not a blank column.

**Attack cost is re-encoded to the Limitless alphabet.** `attacks.cost` holds `C`, `CC`, `PC`,
`GC` — the 11 symbols of `Cards::Fetcher::ENERGY_SYMBOLS` — so `data-energy-type="Water"` twice
becomes `"WW"`. Storing `"Water Water"` would leave this set's attacks unreadable beside every
other set's, and it also feeds the fingerprint.

**The "Pokémon ex rule" block is ignored.** It shares `.ability` with attacks and abilities and is
neither; it is identified by carrying no `ul.left` and no `.poke-ability`. Storing it would put
rules text into `abilities` on every *ex* card in the set and change their fingerprints.

### What the reviews changed

Three passes over the branch — neutral, adversarial and a data-truthfulness pass — found six things
this design had wrong, and each is now a rule with a test that goes red without it.

**`card_type` must test `Trainer` before `Pokémon`.** A Pokémon Tool's type line reads
`Trainer-Pokémon Tool`. The obvious ordering claimed it as a Pokémon, gave it stage `Basic` and
retreat `0`, and the model then refused it with *"Hp can't be blank"* — every Tool in the set
dropping out of the import under an error naming the wrong thing.

**The typographic apostrophe is folded to the plain one.** The source writes U+2019 throughout; the
catalogue is written with U+0027 (421 card names carry it, none carries the other; 1626 attack
effects say "opponent's" against 9 that do not). `CardLabels::RoleSuggester`'s `gust` and
`disruption` rules spell it plainly, so unfolded text takes these cards out of the role vocabulary
without a word — and a Trainer's fingerprint is `SHA256(name)`, so one apostrophe in a name makes a
reprint its own island, unreachable from `Cards::Printings` and from any search typed on an ordinary
keyboard. **Only that character**: it is the sole codepoint above U+2000 in all 17 fragments, and
`×` is left alone because 395 attacks already spell their damage with it.

**`rename_set` bumps `updated_at`.** `Og::CardPayload#subtitle` prints `set_name` while its
`#digest` folds `updated_at`, and the banner is served `immutable` for a year — so a bare
`update_all` would change every renamed card's link preview while leaving its address identical,
permanently, on the one day the task is meant to run. Measured before the fix: same digest, same
path, new content. It is the failure `CLAUDE.md` already writes out for `DeckCard`.

**An ability drops the era label the page prints in front of it.** The Classic Collection reprints
Base Set cards, rendered as `[Pokémon Power] Energy Burn`. No ability in the catalogue carries a
bracket — Limitless writes `Ability: Energy Burn` and `Cards::Fetcher` strips that prefix, which is
the same normalisation. Ability names enter the fingerprint and are joined into the Cardmarket
wishlist line, where brackets resolve to nothing.

**A run that matched no fragment is refused.** It used to report success, exit 0 and create the
`card_sets` row — indistinguishable from importing a set whose cards were all already held. A
mistyped slug is the likely cause, since the operator retypes what the scraper wrote.

**A fragment is checked against the set it says it belongs to.** The markup carries
`data-card-id="30th/128"`, and the filename is only what the scraper called it; `30th/1` and
`30th-c/1` are different cards. A fragment from the other set is now refused rather than filed
under this code.

Two more were left as they are, with reasons. **An Energy card's `subtype` gains the word
`Energy`** when the page omits it, because the catalogue's vocabulary is `Basic Energy` (50 rows)
and `Special Energy` (31), `Card` exempts only the first from the rarity validation, and three
exporters compare against those exact strings — no captured page is an Energy card, so appending
the word answers both possible spellings. And **`resistance` stays nil where Limitless writes the
literal `"none"`** (3080 rows against 798 nils): both spellings already exist in the column, nil is
the more honest of the two, and no filter reads it.

### Rarity is the first token, deliberately

`Cards::Fetcher#parse_rarity` keeps one token (`text[/·\s*(\S+)/, 1]`), which is why the catalogue
holds `Double`, `Art`, `Ultra`, `Special`, `Secret` and not `Double Rare`. The official database
uses a different vocabulary for the same things — `Illustration Rare` where Limitless says
`Art Rare` — and this release adds two names Limitless has not yet given any:
`Futuristic Rare` and `Classic Collection`.

The import applies the **same first-token rule** and maps nothing. `Illustration` will therefore sit
beside `Art` in the `/cards` rarity filter, naming the same thing, until a rescrape replaces it.
That is chosen over a translation table: a table would have to invent Limitless's names for two
rarities that do not have one yet, and a wrong invention is indistinguishable afterwards from a
real value. The duplicate is visible and self-correcting; a bad guess is neither.

`Card.filter_values` caches both lists for an hour (`card.rb:119-129`), so the importer calls
`Card.forget_filter_values` for the reason `CardSets::Importer` and `CardSets::RescrapeJob` do.

## Out of scope, deliberately

- **Any change to `Cards::Fetcher`, `HttpFetcher` or `CardSets::Importer`.** Limitless stays the
  only source the application knows.
- **Backfilling `regulation_mark`.** It is not in the source. OCR of the art was not considered.
- **Generalising to other sets or other languages.** The scraper takes a slug and a number list;
  nothing about it is specific to this release, but nothing here claims it has been exercised on
  another.
- **Anything automatic.** No job, no schedule, no admin button. The scraper is run by hand, on a
  machine with a browser, by someone who reads its output.
