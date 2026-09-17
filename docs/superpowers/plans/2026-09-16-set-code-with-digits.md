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

## The other half, added after review

Adversarial review found the same bug over the same 184 printings on the write path, and the owner
chose to close it here rather than in a follow-up. `Decks::Fetcher::CARD_LINE_RE` wanted
`[A-Z]{2,3}`, and `parse_card_lines` is a `filter_map` whose `next unless match` drops an
unreadable line while `call` raises only when the list parses to *nothing* — so `4 Ultra Ball 30C
128` did not fail an import, it shortened the deck silently.

The shape is now spelled once, as `Decks::Fetcher::SET_CODE`. `Tournaments::LimitlessDecklist` and
`Tournaments::OnlineDecklist` exist to say loudly what that drop hides and both restated the rule
by hand; the three copies diverged, and the day `30C` arrived it was refused by the two guards and
lost by the parser at once. Their `SET_CODE_RE` now reads the shared constant, and a test asserts
the guards refuse exactly what a card line cannot carry — over both alphabets, not by constant
identity, which a fresh literal equal to today's value would satisfy while staying free to drift.

Measured over every printing in the catalogue written out as a card line: **4632 parse under both
shapes with identical captures, 184 parse only under the new one, none stops parsing**. The
remaining 100 are the `GG1`-style numbers, the other half of the same guard, untouched.

`Tournaments::OnlineResults::SET_RE` carries the same shape and is deliberately not unified: it
sanitises a URL segment before a fetch, a different question with the same answer.

## Files

- `app/controllers/concerns/card_searchable.rb` — the shape test and its prose
- `app/services/decks/fetcher.rb` — `SET_CODE` / `SET_CODE_RE` / `CARD_LINE_RE`
- `app/services/tournaments/limitless_decklist.rb`, `.../online_decklist.rb` — guards read the shared shape
- `test/services/search/global_test.rb`, `test/services/decks/fetcher_test.rb` — nine tests
- `CLAUDE.md` — the two paragraphs describing both rules, plus four stale catalogue counts

## Out of scope

- A bare set code listing its whole set (refused by the owner when asked).
- **A genuinely unreadable line is still dropped without a word.** Widening the shape removes the
  184 printings from that class; it does not close the class, and turning the drop into a refusal
  changes the behaviour of every import that ever ran.
- The `GG1`-style card numbers, which are the number half of the same guard.
- `SearchCardsTool`, which takes `set_code` explicitly and already resolved `30C`.
- The `/cards` set filter, which reads `card_sets` and already offers both rows.
