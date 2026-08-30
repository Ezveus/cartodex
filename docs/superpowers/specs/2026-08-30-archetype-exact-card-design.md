# Archetypes designate an exact card, of any type — Design

Issue: #120

## Goal

An `Archetype` must be able to designate **an exact card** — one specific printing, of any `card_type` — where today it can only designate "some printing of a Pokémon named X".

The motivating case is decks whose identity is a Trainer engine rather than an attacker: Lost Zone Box, Ancient Box, Mill/Stall. Those are real archetypes that the current model cannot name.

## Confirmed decisions (from the brainstorming interview)

1. **A member may be any card type** — Pokémon, Trainer or Energy.
2. **The printing is a display reference, not identity.** Identity remains the pair of *fingerprints*. Two archetypes built from two printings of the same pair are duplicates, not siblings.
3. **Uniqueness is enforced in the database**, via denormalised fingerprint columns and a unique index — not by a model validation alone.
4. **Detection splits into two jobs.** Matching an existing archetype becomes type-agnostic; *suggesting* candidates for a new one stays Pokémon-only.

## Facts established before designing (measured, not assumed)

- **The current unique index does not do what it looks like it does.** `(primary_pokemon_id, secondary_pokemon_id)` is UNIQUE, but SQLite treats NULLs as distinct, so two archetypes with the same primary and no secondary are accepted by the database. Verified by inserting the second row with `save(validate: false)`. The only thing preventing that duplicate today is the model validation (`Primary pokemon has already been taken`, also verified) — precisely the race-prone shape this design moves away from.
- **`compute_fingerprint` already covers non-Pokémon**: it hashes name, HP, type, attacks and abilities for a Pokémon and the bare name for everything else. So a fingerprint is a usable identity key for a Trainer or an Energy, and for those cards it is exactly a name match.
- **No MCP tool touches archetypes.** Nothing in `app/mcp/` references them, so that entire surface is outside the blast radius.
- **The colour fallback already exists.** `Decks::ClassificationBadges#archetype_badge` falls back to the neutral `badge-archetype` style when `primary_energy_type` is nil, and `Decks::DeckCard#type_stripe` renders nothing when the type list is empty. A Trainer-led archetype degrades correctly with no change. This was on the issue's checklist and is not work.

## Data model

### Renaming

`primary_pokemon_id` → `primary_card_id`, `secondary_pokemon_id` → `secondary_card_id`; associations become `primary_card` / `secondary_card`.

One trap: `Archetype.search` writes its join alias by hand.

```ruby
"OR secondary_pokemons_archetypes.name_normalized #{like}"
```

That alias is derived from the association name, so renaming breaks the scope **at query time, not at load time**. It needs a test that actually runs the scope.

### Denormalised fingerprints

Add `primary_fingerprint` (NOT NULL) and `secondary_fingerprint` to `archetypes`, filled from the associated cards by the existing `before_validation`, with a UNIQUE index on the pair.

**A missing secondary is stored as the empty string, not NULL.** Given the measurement above, a NULL would reproduce exactly the hole this design exists to close.

**These columns back the index and nothing else.** Detection reads `cards.fingerprint` through a join — the live truth — and never the copy. This is what makes fingerprint drift tolerable: a `force: true` rescrape that corrects an attack changes a card's fingerprint, but since nothing *decides* anything from the denormalised value, the only consequence is a uniqueness constraint reasoning on slightly stale data. A resync task (rake or admin action) recomputes the columns and reports collisions, rather than a Card callback failing a whole set rescrape halfway through.

### Backfill

The migration copies fingerprints from the associated cards, then — **before** adding the index — detects the duplicates the broken index has been letting through. If it finds any, it fails and names them rather than dropping one: `decks` and `deck_results` point at these rows, so deleting one silently reassigns somebody's data.

## Detection

`Decks::ArchetypeDetector` currently conflates two jobs under one name. They are separated, because the false-positive risk is not the same on each side.

**Matching** — is there an existing archetype for this deck? The archetype's members were chosen by a human, so containment is a safe question: no false positive can come from the card pool, only from a badly defined archetype, which is a data problem.

It becomes type-agnostic and keyed on fingerprints. The query keeps its current shape — a join on the primary filtered by `cards.fingerprint` (the `index_cards_on_fingerprint` index already exists), with the secondary checked in Ruby as it is today — but it is fed **every** card in the deck rather than only its notable Pokémon, and it compares fingerprints rather than names. Comparing fingerprints is also strictly more correct than today's `where(cards: { name: names })`, which conflates unrelated cards sharing a name.

**Scoring** carries the guard against junk archetypes. Each member is weighted by how much it identifies a deck:

| member | weight |
|---|---|
| rule-box Pokémon | 3 |
| other Pokémon | 2 |
| Trainer / Energy | 1 |

The score is the sum; a secondary that is absent from the deck disqualifies, as today. So *Gardevoir ex / Munkidori* scores 6, *Gardevoir ex* alone 3, *Lost Zone Box* (Comfey / Colress's Experiment) 3, and a badly-defined "Iono" archetype 1 — it can only win when nothing else matches at all. Ties on the sum are broken by member count, which preserves today's intent that a two-member archetype beats a one-member one.

**Suggestion** does not change. `notable_pokemon` keeps ranking rule-box first, then HP, then copies, and keeps filtering to Pokémon. Ranking Trainers by copy count would propose Iono, Professor's Research and Ultra Ball on every deck ever imported. A Trainer-led archetype is created by hand; once it exists, matching finds it on its own.

**`Result` gets clearer names.** `archetype` now comes from the whole deck while `primary`/`secondary` come only from the notable Pokémon; those two become `suggested_primary` / `suggested_secondary` so the struct does not read as if all three describe the match. Two call sites.

## UI and API

`Ui::PokemonSelect` becomes `Ui::CardSelect`, with an optional `type:` filter instead of a hardcoded one. Three call sites (the admin archetype form, the deck archetype field, the deck result modal), each with its own Stimulus controller repeating `/api/cards?q=…&type=Pokémon` — the type moves to a `data` attribute.

Server-side there is nothing to add: `Api::CardsController#index` already accepts an optional `type`, and `card_json` already returns `set_name`, `set_number` and `image_url`. Only the JS rendering of the results list changes, to show set and number — now necessary, since several rows carry the same name.

**The one non-mechanical change is in `Api::ArchetypesController#create`:**

```ruby
archetype = Archetype.find_or_initialize_by(primary_pokemon: primary, secondary_pokemon: secondary)
```

That lookup is by card id. Since identity is now the fingerprint pair, picking a different printing of the same card would look like a new archetype, go to `save!`, and be refused by the unique index — a 500 where the user merely re-designated a card they own. The lookup must be on the fingerprint pair, creating only when nothing matches. When it finds one it returns it, which is already what the current code intends; only the key is wrong.

The rest is mechanical: the `card_type: "Pokémon"` scope disappears from both `find` calls, the `primary_pokemon_id` / `secondary_pokemon_id` params follow the column rename on both sides, and `archetype_json` stops returning bare names so a chosen printing is identifiable.

## Out of scope

- **A commonness guard** disqualifying cards that appear in more than N% of the user's decks (approach 2 in the interview). It would let *suggestion* propose Trainers, but it needs a threshold and produces no signal on a small collection.
- **Teaching the detector to suggest Trainer-led archetypes** at all.
- **A minimum copy count** for a member to count as present. See the seam below.

## Known seams

- **Matching becomes more permissive.** Fed the whole deck, it will match an archetype whose primary is played as a single tech copy. The weighted score contains the damage — a 1-of only wins when nothing better matches — and this is accepted deliberately. A copy-count filter is the refinement if it shows up in practice.
- **Fingerprint drift** leaves the denormalised columns stale until the resync task runs. Harmless by construction (see Data model), but it means the unique index can briefly permit a duplicate that the resync will then report.
- **`Archetype.search`'s hand-written alias** is the kind of thing that breaks silently. It needs a test that executes the scope, not just one that builds it.

## Testing

- The renamed scope `Archetype.search` **executed**, matching on archetype name, primary card name and secondary card name.
- A non-Pokémon member: creation through the API, the badge falling back to the neutral style, the stripe rendering nothing.
- Uniqueness at the database level: a second archetype on a different printing of the same pair is refused with validations skipped.
- The empty-string sentinel: two single-member archetypes on the same primary are refused, which is the case today's index misses.
- Matching: an archetype pinned to one printing matches a deck holding another; a Trainer-led archetype matches; a rule-box Pokémon archetype outranks a Trainer-only one on the same deck; a secondary absent from the deck disqualifies.
- Suggestion: unchanged behaviour, and specifically that it never proposes a Trainer.
- `Api::ArchetypesController#create` returns the existing archetype when given a different printing of the same pair, rather than raising.
- The migration's duplicate detection: it fails and names the offenders rather than dropping a row.
