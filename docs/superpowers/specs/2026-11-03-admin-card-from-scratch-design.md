# Admin: create a card from scratch, and edit all of it

## What

From an admin card-set page (`/admin/card_sets/:id`), a **New card** button opens a form that
creates a printing in that set without Limitless. The same form, rendered by `Admin::Cards::Form`,
now edits a card too, so edit gains every field create has — attacks and abilities included.

## Why the form is this wide

`Card#compute_fingerprint` is a `before_save` that hashes a Pokémon's name, HP, type **and its
attacks and abilities** (`app/models/card.rb`, `CLAUDE.md` — Models). A Pokémon saved without them
takes the fingerprint of a card that has none, and nothing re-derives it: it is invisible to
`Decks::ArchetypeDetector` and `Cards::Printings`. A create form limited to the nine fields the edit
form had would therefore produce a wrong Pokémon every time. The owner chose the full form, with
fixed slots and no JavaScript, and asked that edit get the same fields.

## Measured (development catalogue, 5223 cards, 2026-11-03)

| | 0 | 1 | 2 | 3 |
|---|---|---|---|---|
| Pokémon by attack count | 4 | 2206 | 2176 | 2 |
| Pokémon by ability count | 3280 | 1068 | 40 | — |

Trainers carry them too: 2 Tools hold an attack (Technical Machine: Fluorite, Core Memory), 8
fossil Items hold an ability. So the slots are offered whatever the card type, and
**3 attack slots + 2 ability slots** cover the whole catalogue. An edited card holding more than
that is shown with as many slots as it has, so editing never drops one.

Stage values in the catalogue: `Basic`, `Stage 1`, `Stage 2`, `VSTAR`, `VMAX`, `EX`, `BREAK`.
Subtype values: `Item`, `Tool`, `Supporter`, `Stadium`, `Special Energy`, `Basic Energy`. Both are
validated elsewhere by exact string (`stage == "BREAK"`, `subtype == "Basic Energy"`), so they are
selects over `Card::STAGES` / `Card::SUBTYPES`, and an edited card whose current value is outside the
list keeps it as an option.

## Rules

- **One writer**, `Cards::ManualWriter`, used by both create and update. It assigns the columns,
  replaces attacks and abilities from the slots, sets `pokemon_subtype` through
  `PokemonSubtype.for_card_name` for a Pokémon (nil otherwise — the rule `Cards::OfficialImporter`
  follows), saves **once**, and on success calls `Card.forget_filter_values` (a new rarity or
  regulation mark must reach the `/cards` filter).
- **Update is all-or-nothing.** Replacing attacks deletes rows before the card saves, so the
  replacement and the save run in one transaction, rolled back when the card is refused; the
  re-rendered form shows what was typed.
- **A slot is ignored when all its fields are blank**, and refused (`errors[:base]`, naming the
  slot) when it has content but no name — silently dropping typed text is not acceptable.
- **Slot shapes follow `Cards::Fetcher`**, so a hand-made printing fingerprints like a scraped
  reprint: positions are 0-based over kept slots, values are stripped, blank damage and effect are
  nil, and **a named attack with a blank cost is stored as `"0"`** — the way Limitless writes its free
  attacks; an empty string would give the card a fingerprint no other printing shares.
- **Every successful update bumps `updated_at`**, even when only an attack's text changed:
  `Og::CardPayload#digest` folds `updated_at` and the banner is served immutable.
- **A fingerprint moved by an edit is reported, not repaired.** Label assignments and archetypes
  are keyed on fingerprints and their resync tasks walk the whole catalogue; the edit already moved
  fingerprints before this change (name, HP, type). The update notice names both tasks —
  `card_labels:resync_fingerprints`, `archetypes:resync_fingerprints` — when it happened.
- **On create the set is the page's set.** `card_set` comes from the URL, `set_name` is pre-filled
  with its code and `set_full_name` is set to its name. Edit keeps the set select and set fields.

## Surface

`resources :cards, only: %i[new create]` nested under `admin/card_sets` →
`new_admin_card_set_card_path(set)`, `admin_card_set_cards_path(set)`, served by
`Admin::CardsController#new`/`#create`. `AdminGateTest` walks the routing table and covers them
with no list to update.

## Out of scope

Deleting a card from the admin panel; showing attacks on the admin card page (the public card page
shows them); automatic fingerprint resync.
