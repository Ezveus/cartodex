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

## What actually changes answer

Enumerated rather than argued, over every (set code x set number) pair the catalogue holds: **368
query shapes**, every one of them empty before and answering now, none of them answering a
*different* card than before.

| Shape | Gained | Lost |
|---|---|---|
| `CODE NUMBER` — "30C 128" | 184 | 0 |
| `<name> CODE` — "Exeggcute 30C" | 184 | 0 |

The second class is the one the change reaches without being written for it, and it is the same
behaviour "Exeggcute ASC" already had.

## Why the collision argument does not get worse

`CLAUDE.md` records the trade this predicate makes: where a token reads both as a set code and as a
fragment of a card name, the set wins, and 12 of the imported codes are substrings of card names.
Widening the charset can only newly capture a token that both matches the wider regex *and* answers
`Card.in_set_code(...).exists?`. Only `30C` and `30CC` do, and no card name contains either. The
delta to that trade is therefore zero collisions, and the `.exists?` guard — not the regex — remains
what carries the safety, which is the argument the file's own comment already makes.

## Tests

`test/services/search/global_test.rb` is where this predicate is pinned; the comment above its
length-bound test quotes the regex literally and has to move with it. Attacking the plan replaced
three of the four cases first written here, each because the assertion as drafted could not
discriminate:

1. **A digit code is read as a code** — asserted as *which* card, against a decoy named
   "Bonus 30c Promo" filed under another set at the same number. Found-versus-empty passes under
   the name reading.
2. **A numeric token no set answers to falls back to being a name** — asserted so the *name* is
   the observable winner, because both readings of such a token answer nothing and an
   `assert_empty` stays green with the database probe deleted outright.
3. **A numeric token a set does answer to is read as a code** — the only case separating this
   charset from one demanding at least one letter.
4. **The lower edge of the length bound** — the drafted "both edges with digits" added nothing the
   existing six-character row already caught; narrowing to `{1,5}` changed no result in the file,
   so a one-character code was free. A printing filed under `X` is what pins it.
5. **A token past the bound is refused before the database is asked** — the regex being the cheap
   left operand of the `&&` was unpinned; swapping the operands changes no result anywhere.
6. **A digit-bearing token that names no set costs exactly one probe** — the price, recorded.
7. **The prose quotes the predicate that is compiled** — by equality against `SET_CODE_SHAPE`,
   not by a list of forbidden spellings, so widening the bound reddens the quotation.

All seven mutation-verified: every mutation aimed at them went red, none survived.

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
