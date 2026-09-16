# Let a set code carry digits

## The problem, measured

`CardSearchable#card_set_code?` (`app/controllers/concerns/card_searchable.rb:47`) decides whether a
token in a free-text card query names a set. It tests `/\A[a-zA-Z]{2,5}\z/` before asking the
database, so a code carrying a digit can never be read as a code at all.

Two such codes now exist in the catalogue, both written by the 30th Celebration import (PR #188):
`30C` (154 cards) and `30CC` (30 cards). Measured on the development catalogue, 2026-09-16:

| Figure | Value |
|---|---|
| Distinct `cards.set_name` values | 56 |
| …carrying a digit | 2 (`30C`, `30CC`) |
| Cards behind those two codes | 184 |
| Card names containing `30c` | 0 |
| Card names containing `30cc` | 0 |
| Distinct codes that are purely numeric | 0 |
| Code lengths | 3 (55 codes), 4 (1 code) |

And the behaviour, through `Search::Global` against that catalogue:

```
"30C 128"  -> 0 cards
"30CC 1"   -> 0 cards
"POR 56"   -> 1 card (Honedge POR 56)
```

## The change

One character class:

```ruby
token.match?(/\A[a-zA-Z0-9]{2,5}\z/) && Card.in_set_code(token).exists?
```

Three things this deliberately does **not** change.

**The length bound stays `{2,5}`.** It is what rejects a token before the query, and the existing
test pins both of its edges. `30CC` is four characters.

**A single token is still a name.** `apply_card_name_filter`'s two guards
(`tokens.length > 1 || number`) are untouched, so `/cards?q=30C` remains a name search, exactly as
`/cards?q=ASC` is today. Widening that is a separate decision affecting all 56 codes, and the owner
refused it when asked.

**A purely numeric token stays admissible.** `[a-zA-Z0-9]`, not "at least one letter". Today this is
a no-op — no set answers to a numeric token, so `.exists?` refuses and the query stays a name search
— and `Tournaments::OnlineResults::SET_RE` is already spelled `/\A[A-Z0-9]{2,5}\z/`, so the
repository has the precedent. Issue #111 (Japanese sets) is what would make it live: SV2a is
literally named "151".

## Why the collision argument does not get worse

`CLAUDE.md` records the trade this predicate makes: where a token reads both as a set code and as a
fragment of a card name, the set wins, and 12 of the imported codes are substrings of card names.
Widening the charset can only newly capture a token that both matches the wider regex *and* answers
`Card.in_set_code(...).exists?`. Only `30C` and `30CC` do, and no card name contains either. The
delta to that trade is therefore zero collisions, and the `.exists?` guard — not the regex — remains
what carries the safety, which is the argument the file's own comment already makes.

## Tests

`test/services/search/global_test.rb` is where this predicate is pinned; the existing test at
line 195 quotes the regex literally in its comment and has to move with it.

1. **A code carrying digits is read as a code.** Query `"30C 128"` finds the printing. The fixture
   card's name must not contain its own code, or the assertion passes as a name match.
2. **A purely numeric token is a name until a set answers to it.** Two halves, because the guard
   being asserted is `.exists?` and not the regex: with no set named `151`, `"151 10"` does not
   reach the card numbered 10 in some other set; with a card filed under `set_name = "151"`, the
   same query reaches it.
3. **The length bound still holds at both edges with digits present** — extend the existing
   edge test rather than duplicating it.

Every one of these is sabotage-verified: restore `[a-zA-Z]`, watch it go red, restore.

## Files

- `app/controllers/concerns/card_searchable.rb` — the regex and its comment
- `test/services/search/global_test.rb` — the three cases above
- `CLAUDE.md` — the sentence describing this rule says "2-5 **letter** fragment"
- `docs/superpowers/plans/2026-09-16-set-code-with-digits.md` — this file

## Out of scope

- A bare set code listing its whole set (refused above).
- `SearchCardsTool`, which takes `set_code` explicitly and already resolves `30C` through
  `Card.in_set_code`.
- The `/cards` set filter, which reads `card_sets` and already offers both rows.
