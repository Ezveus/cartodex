# A deck's build odds — `/decks/:id/odds` — Design

Issue: none — requested directly.

## Goal

`/decks/:id/stats` answers "how did this deck do", from `DeckResult` rows. Nothing in the app
answers "how does this deck *open*" — the question a player asks while building it, before a single
match has been played. This change adds a sibling page that answers it from the decklist alone:
the mulligan rate, the chance of holding a given card on turn one, the chance a card is sitting in
the prizes where it cannot be reached, and the chance of assembling a named combination by a named
point in the game.

Every number on the page is exact and closed-form. Nothing is simulated, nothing is sampled.

## The model

One assumption carries the whole feature: **the deck is a uniform random permutation of its `N`
cards**, and the deal reads positions off it.

```
position   1 … 7      8 … 13        14 …
           hand       prizes        draw pile, in order
```

Three consequences, and each of them is what makes a section of the page computable:

1. **"Accessible after `d` draws" is a fixed set of positions.** `{1..7} ∪ {14..13+d}`. The cards
   at any *fixed* set of `a` positions form a uniform `a`-subset of the deck, so accessibility is a
   plain hypergeometric question — no simulation, no recursion over turns.
2. **A prize is not permanently lost.** Taking a prize card puts it in hand. Taking `p` prizes adds
   a uniform `p`-subset of `{8..13}` to the accessible positions. That subset is random, but it is
   *independent of the permutation*, so conditioning on it leaves a fixed position set — and the
   accessible cards are still a uniform `(7+d+p)`-subset. **`d` and `p` enter the formula the same
   way.** They are kept as separate controls anyway; see *Why prizes keep their own axis*.
3. **The mulligan conditions the hand and nothing else.** A hand with no Basic Pokémon is never
   kept, so the hand is a uniform 7-subset *conditioned on containing at least one Basic Pokémon*.
   Positions 8 and up are untouched by the condition.

### The closed form

Let `N` = deck size, `b` = Basic Pokémon in the deck, `h` = 7, and `a_rest = d + p`. For a target
set of `k` cards of which `k_other` are **not** Basic Pokémon:

```
P(no Basic in hand)            = C(N−b, h) / C(N, h)
P(target inaccessible)         = C(N−k, h)/C(N, h)            × C(N−h−k, a_rest)/C(N−h, a_rest)
P(target inaccessible ∧ no Basic in hand)
                               = C(N−b−k_other, h)/C(N, h)    × C(N−h−k, a_rest)/C(N−h, a_rest)

P(target accessible | hand is keepable)
    = [ P(keepable) − P(inaccessible) + P(inaccessible ∧ no Basic) ] / P(keepable)
```

The first factor of each product is the hand, which must avoid the target *and* — in the second
line — every Basic. The second factor is the rest: given the hand, the remaining `N−h` cards still
hold all `k` target cards, and the `a_rest` accessible positions among them must avoid the target.
`k_other` is what makes the two lines differ, and it is the only place the overlap between the
target and the Basics appears.

**A fingerprint group is homogeneous in `stage`**, so for a single card group `k_other` is either
`0` or `k`. A role bucket can be genuinely mixed, and the formula above already covers it.

### Combinations: AND of OR-buckets

For disjoint buckets `B₁…B_m`, "at least one accessible card in every bucket" expands by
inclusion–exclusion over subsets `S` of the buckets, each term being the formula above applied to
the union `U_S` (sizes add, the buckets being disjoint):

```
P(every bucket hit ∧ keepable) = Σ_S (−1)^|S| [ P(U_S inaccessible) − P(U_S inaccessible ∧ no Basic) ]
```

`m ≤ 4`, so at most 16 terms. Disjointness is what makes `|U_S|` a sum rather than a
set-union computation, and it is the reason the UI must enforce it.

### Verification

Both forms were checked against **exhaustive enumeration of every permutation** of 8-card decks
(all 40 320, averaged over every choice of which prizes are taken), in exact `Rational` arithmetic:

| Shape | Cases | Result |
| --- | --- | --- |
| Single group, target disjoint from the Basics | 3 | exact equality |
| Single group, target ⊆ Basics | 2 | exact equality |
| Single group, mixed (one Basic copy, one not) | 1 | exact equality |
| Single group, every prize taken | 1 | exact equality |
| Inclusion–exclusion, 2 and 3 buckets, bucket containing a Basic, all prizes taken | 4 | exact equality |

Equality, not agreement to some tolerance. This is the check `deal_test.rb` reproduces.

## The measurements

All on a 60-card deck, computed with the formulas above.

**Why the model is conditional and not naive.** The gap is not a rounding detail — it is nearly ten
points on exactly the cards a player cares most about:

| Group | Naive `1 − C(56,7)/C(60,7)` | Conditional | Gap |
| --- | --- | --- | --- |
| 4 copies, not a Basic | 39.95 % | 38.06 % | −1.89 pt |
| 3 copies, not a Basic | 31.54 % | 29.94 % | −1.61 pt |
| 1 copy, not a Basic | 11.67 % | 10.98 % | −0.69 pt |
| 1 copy, Basic Pokémon | 11.67 % | 14.41 % | **+2.75 pt** |
| 3 copies, Basic Pokémon | 31.54 % | 38.97 % | **+7.43 pt** |
| 4 copies, Basic Pokémon | 39.95 % | 49.36 % | **+9.41 pt** |

(12 Basics in the deck.) A naive table tells a player their 4-of starter shows up in half the
opening hands it actually does. That is the single strongest reason the extra `k_other` term exists.

**Mulligan rate**, the headline number of the opening panel:

| Basic Pokémon | Mulligan rate | Mean mulligans |
| --- | --- | --- |
| 8 | 34.64 % | 0.530 |
| 10 | 25.86 % | 0.349 |
| 12 | 19.06 % | 0.236 |
| 14 | 13.86 % | 0.161 |
| 16 | 9.92 % | 0.110 |
| 18 | 6.99 % | 0.075 |

**Prize risk**, and why singletons get their own panel:

| Copies | At least one prized | All prized |
| --- | --- | --- |
| 1 | 10.00 % | **10.00 %** |
| 2 | 19.15 % | 0.847 % |
| 3 | 27.52 % | 0.058 % |
| 4 | 35.15 % | 0.003 % |

**Cost.** 2 000 evaluations in exact `Rational` arithmetic take **10.1 ms**. A whole deck's report
precomputes every curve over the full range of `a_rest` (0…53), so about 25 groups × 54 points
≈ 1 350 evaluations, ≈ 6.8 ms. Precomputing all of it is cheaper than the page render around it,
which is what makes the client-side controls possible without a single line of duplicated
mathematics.

## What the page refuses to say

Four states where the page names its own incapacity rather than printing a number:

- **No Basic Pokémon.** The mulligan loop never terminates, so every conditional probability is
  `0/0`. The page says the deck cannot start a game and renders nothing else.
- **`N ≠ 60`.** The numbers are computed against the real `N` and a notice names the gap. This is
  not an edge case to tolerate but the normal state of a deck under construction, which is when the
  page is most useful.
- **`N < 13`.** No prize section — there are not enough cards to deal one.
- **Partial role curation.** `card_labels` of family `role` cover ≈ 94 fingerprints, not the
  catalogue. The role panel prints how many of the deck's cards carry no role label, because a
  `search` count of 4 in a deck playing 12 uncurated searchers is a lie by omission.

And four limits of the model itself, stated on the page rather than left to be discovered:

- **Draw effects are not modelled.** The scenario controls are the only way draw enters the page;
  nothing infers that the deck plays Professor's Research. The manual input *is* the admission.
- **Iono and Lillie's Determination are approximated, upward.** Drawing off the top is exactly "`d`
  more cards in the prefix". Shuffling the hand back in and redrawing is not: already-seen cards
  become drawable again, so the true probability of having seen a given card is *lower* than the
  page says. Professor's Research, which discards rather than shuffles, is exact.
- **"Seen" is not "held".** A card reached and then discarded to Professor's Research counts as
  accessible. This matters most to the combo calculator, which answers "I have seen one of each"
  and not "I hold them simultaneously".
- **Opponent mulligans are not modelled** — they hand out extra cards, and how many depends on the
  other deck.

## Services

Four classes under `app/services/decks/odds/`.

| Class | Responsibility | Touches AR |
| --- | --- | --- |
| `Decks::Odds::Deal` | The model. `N`, `b`, `h`, `prize_count`, and every formula above. Knows nothing of `Deck` or `Card`. | no |
| `Decks::Odds::Groups` | Deck → groups keyed on `Card#fingerprint`, quantities summed across printings, each carrying `copies`, `basic?`, `card_type` and its role slugs. | yes |
| `Decks::Odds::Report` | The page payload: opening aggregates, per-group curves, role buckets, prize risk. `ApplicationService`. | yes |
| `Decks::Odds::Combo` | Parses `?combo=`, enforces disjointness and the cap, returns one curve. `ApplicationService`. | yes |

`Deal` holding no Active Record is the point of the split: it carries all of the mathematical risk
and is testable by enumeration, with no fixtures and no database.

**`Groups` keys on `fingerprint`**, the app's existing "same card, any printing" key — 2 Iono (PAL)
plus 2 Iono (PAF) is one group of 4 copies, which is what the rules and the probabilities both say.
This is the same key `Decks::ArchetypeDetector` matches on. A card whose `fingerprint` is nil (only
reachable through a callback-bypassing write) falls back to its own `card_id`, so it forms a group
of its own rather than merging with every other nil.

**`Groups` counts a Basic Pokémon as `card_type == "Pokémon" AND stage == "Basic"`, never `stage`
alone.** Measured on the development catalogue: 2 196 Pokémon carry `stage = "Basic"` — and so do
**50 Basic Energy cards**. Testing `stage` alone counts a deck's basic Energy toward the mulligan,
which makes the mulligan rate wrong in the reassuring direction, by a lot, on exactly the decks
that play the most Energy.

## The page

`GET /decks/:id/odds`, a member route on `resources :decks`.

### Scenario controls

One compact row, three steppers feeding one integer, with the integer shown:

```
Turn [ 3 ]   + effect draws [ 7 ]   Prizes taken [ 1 ]
                          → 18 cards seen (7 hand + 10 drawn + 1 prize)
```

`d = turn + effect_draws`, `p = prizes_taken`, clamped to `d ≤ N − h − prize_count` and `p ≤ 6`.
**Turn `N` is `N` draws**: since Sun & Moon both players draw on their first turn, only the attack
is withheld from the player going first. There is no first/second control, because there is no
first/second difference to model.

The printed total is the honest line: it is literally the number that enters the formula.

### Why prizes keep their own axis

`d` and `p` are mathematically interchangeable (§ The model, consequence 2), so folding them into
one "+X cards gained" control would give identical numbers. They are kept apart for two reasons.
The caps differ — `p ≤ 6`, `d ≤ 47` — and a merged control cannot clamp either correctly. And the
prize panel's whole point is a sentence that a merged control makes unsayable: a one-of ACE SPEC is
10.00 % unreachable at zero prizes taken, 5.00 % at three, and 0 % at six.

### Sections

1. **Opening** — mulligan rate, mean mulligans, Basic Pokémon count.
2. **By role** — one row per role present in the deck: card count, P(≥1 in the opening hand),
   P(≥1 accessible), plus the coverage line.
3. **Prize risk** — groups ordered by P(all copies unreachable) descending, reacting to the prizes
   taken control.
4. **Per-card table** — one row per fingerprint group: name, copies, P(in opening hand),
   P(≥1 prized), P(all prized), P(accessible).
5. **Combination calculator** — in a Turbo Frame.

### The controls are an index lookup

**One curve serves all three controls.** `d` and `p` enter the formula only through their sum, so a
group's accessibility is a function of the single index `a_rest = d + p` — the three steppers move
one index between them. Each reactive cell carries its whole curve in `data-curve='[…]'`, indexed
0…53, and a `deck-odds` Stimulus controller writes `cell.textContent = curve[a_rest]`. The prize
columns are the exception: "all copies still unreachable" is a question about the prize block
itself, not about accessibility, so those cells carry a second, 7-point curve indexed by `p` alone.

**No mathematics in JavaScript** — the repo has no JS test infrastructure, only system tests, so a
second implementation of the conditional hypergeometric would be held down by nothing. Payload:
≈ 10 KB of `data-curve` attributes for a 60-card deck.

## The combination calculator

Buckets are composed bucket-first: each bucket is a stacked block holding chips for the cards in
it, plus an "Add" control opening a client-side filterable list of the deck's own groups, with
cards already used elsewhere greyed out. "New bucket", up to 4. No catalogue search and no network
call — the deck has ~25 groups, so the list ships with the page.

`Ui::CardSelect` is deliberately **not** reused: it searches the whole catalogue through the API,
which is the wrong population here. Its shape (input plus results dropdown) is the idiom being
followed.

A `deck-combo` controller serialises the assignment into one short param and navigates the frame:

```
?combo=fp1.fp2.fp3|fp4.fp5
```

**Disjointness is enforced client-side *and* re-checked on the server.** The picker greys out a
used card, but the param is a URL and the picker is not a guarantee — a fingerprint appearing in
two buckets, a fingerprint not in this deck, an unparseable param or more than 4 buckets each fail
closed into an error frame. Never a number computed from a misread request.

The frame's response ships its own curve, so the scenario controls keep moving the combination's
probability without a second request.

## Public surface

`resources :decks` already sits outside `authenticate :user`, so `:odds` rides out with it. Per
`docs/architecture/public-surface.md` the action must therefore:

- be named in `publicly_reachable :show, :export, :shared, :odds`;
- look the deck up with the unscoped `Deck.find_by!(key: params[:id])` and `authorize @deck, :show?`
  on the next line, nothing before it — this becomes the *third* unscoped deck lookup in the app,
  after `#show` and `#export`;
- reuse `DeckPolicy#show?` (`owner? || record.shared?`) rather than growing an `odds?` of its own:
  the page is a pure function of the decklist, which `#show` already renders in full, so a separate
  rule could only ever disagree with itself. `DeckPolicy#stats?` stays `owner?` and is untouched;
- carry a **rate limit**, unlike `#show`. The existing comment exempts `#show` because it is "one
  page load per click, with no live control behind it". The scenario controls are client-side and
  emit nothing, but the combination calculator *is* a live control, so 30/min for anonymous readers,
  matching `EXPORT_RATE_LIMIT_TO` and for the same reason: a click, not an automatic fire, over a
  whole deck's preload;
- gain a case in `test/controllers/public_access_test.rb`, on both the signed-out and signed-in
  halves.

Links: `decks#show` gains an "Odds" entry for every reader; `decks#stats` keeps its owner-only
"Match stats" link. An ownerless tournament field list is `shared` by construction, so the page
works for it — which is the population it is most interesting on.

## Testing

- **`test/services/decks/odds/deal_test.rb`** — the keystone. Closed form versus exhaustive
  enumeration of every permutation of small decks, for every overlap shape in the verification
  table, in `Rational` equality. Plus the 60-card reference values from *The measurements*, plus the
  refusals: zero Basics, `N < 13`, `d` and `p` beyond their clamps.
- **`test/services/decks/odds/groups_test.rb`** — printings of one card merge into one group;
  **Basic Energy is not a Basic Pokémon**; a nil fingerprint does not merge.
- **`test/services/decks/odds/report_test.rb`** — aggregates agree with `Deal`; role coverage count.
- **`test/services/decks/odds/combo_test.rb`** — inclusion–exclusion against enumeration;
  disjointness, cap and malformed params all fail closed.
- **`test/controllers/decks_controller_test.rb`** — owner, visitor on a shared deck, visitor on a
  private deck (404), unknown key (404), and a **flat-cost test** pinning the query count, measured
  identical on a 10-card and a 60-card deck.
- **`test/components/decks/odds_view_test.rb`** — the four refusal notices render.
- **`test/system/deck_odds_test.rb`** — the scenario controls change displayed numbers without a
  request; the combination calculator returns one. **At both viewports**, using `click_nav_link`
  and never clicking a nav link directly.

Every added test is sabotage-checked — the mechanism it claims to hold is broken, the test is
confirmed red, the break is reverted — before the work is called done.

## Rejected

- **A Monte Carlo simulator.** Would let draw Supporters be modelled properly, at the cost of
  sampling error on every number and a far larger feature. The closed form is exact; the honest
  caveat is cheaper than an inexact engine.
- **Computing in JavaScript.** Instant combos, but a second implementation of the mathematics in a
  repo with no JS tests.
- **Everything server-rendered, slider included.** Consistent with `/archetypes`, but a network
  round trip per notch kills the exploration the page exists for. Precomputed curves get both.
- **A naive `7 of 60` table.** Simpler and wrong by up to 9.41 points on Basic Pokémon.
- **Grouping rows by printing.** Splits 2 Iono + 2 Iono into two 2-ofs and understates every number
  about them.
- **A segmented `— / A / B / C` control per row.** Makes disjointness structural, but means scanning
  25 rows to assign 4 and gives no name to what a bucket means.
