# A deck's build odds — `/decks/:id/odds`

`/decks/:id/stats` answers "how did this deck *do*", from `DeckResult` rows. This page answers "how
does it *open*", from the decklist alone — the question a player asks while building, before a
single match has been played. Every number on it is exact and closed-form: nothing is simulated,
nothing is sampled, all internal arithmetic is `Rational`, and the only conversion to `Float` is the
one rounding to two decimal places for display.

The design spec is `docs/superpowers/specs/2026-09-12-deck-odds-design.md`; it carries the
derivation of every formula and the tables the tests assert against. The implementation plan and the
record of what attacking it found are `docs/superpowers/plans/2026-09-12-deck-odds.md`.

## The model, and the three things it makes computable

One assumption carries the whole feature: **the deck is a uniform random permutation of its `N`
cards**, and the deal reads positions off it — hand at 1…7, prizes at 8…13, draw pile from 14. Three
consequences, each of which is what makes a section of the page computable at all:

1. **"Accessible after `d` draws" is a *fixed* set of positions**, `{1..7} ∪ {14..13+d}`. The cards
   at any fixed set of `a` positions form a uniform `a`-subset, so accessibility is a plain
   hypergeometric question — no simulation, no recursion over turns.
2. **A prize is not permanently lost.** Taking `p` prizes adds a uniform `p`-subset of the prize
   block, random but independent of the permutation, so `d` and `p` enter every formula through
   their **sum**. They keep separate controls because their *ceilings* differ — `p ≤ 6` while
   `d ≤ N − 13` — not because the mathematics distinguishes them.
3. **The mulligan conditions the hand and nothing else.** A hand with no Basic Pokémon is never
   kept, so the hand is a uniform 7-subset conditioned on containing at least one Basic, and the
   positions after it are untouched by that condition.

**The conditioning is the whole point, and it is worth up to 9.41 points.** A naive "at least one of
4 among 7 of 60" says a four-of shows up in 39.95 % of opening hands; conditioned on the hand being
keepable it is **49.36 %** when the card is a Basic Pokémon and 38.06 % when it is not. The gap is
largest on exactly the card a player cares most about.

## Four services, and why `Deal` is alone among them

| Service | Answers |
|---|---|
| `Decks::Odds::Deal` | the probability model — a deck size, a Basic count, a hand size, a prize count |
| `Decks::Odds::Groups` | a deck folded into fingerprint-keyed card groups |
| `Decks::Odds::Report` | the page payload: a whole *curve* per group over every reachable scenario |
| `Decks::Odds::Combo` | the combination param, parsed, and inclusion–exclusion over its buckets |

**`Deal` must never reference `Deck`, `Card` or Active Record**, and that constraint is what buys
the feature its verification. Because it takes plain integers, `deal_test.rb` checks **every
formula against exhaustive enumeration of all 40 320 permutations of an 8-card deck**, in exact
`Rational` arithmetic — the assertions are equalities, not agreements to a tolerance. That is also
why `Deal` takes `hand_size:` and `prize_count:` at all: enumerating a 60-card deck is 60!
permutations, and an 8-card deck dealt a 7-card hand leaves no prize block. The *shape* of the
question is identical at both sizes.

`Deal` refuses rather than answering `nil`. `#playable?` is false for a deck with no Basic Pokémon
(the mulligan loop never terminates, so every conditional probability is 0/0) and for a deck of
fewer than `hand_size + prize_count` cards (`C(N, 7) = 0`, a division by zero). Both are reachable
from the UI — the second is **every deck in the minute after it is created** — and every probability
method raises `Deal::Unplayable`. A `nil` silently formatted as "0.00 %" is the failure that guard
exists to prevent.

**`accessible` is a delegation to `all_buckets`, not a formula of its own.** Every row of the
per-card table is the one-bucket case of the combination calculator, and a projection that disagreed
with the calculator would warn the reader about the wrong thing — the same rule
`Allocations::Backing` enforces for the deck page.

**One term in `Deal` is the single most likely way to get the file wrong**, and it has a test of its
own: `inaccessible_and_no_basic` subtracts `non_basic_copies`, not `copies`, because a target copy
that *is* a Basic Pokémon is already excluded by `basics` and counting it twice is silent. The mixed
row of the enumeration test — a target holding one Basic and one non-Basic — is the only assertion
that discriminates it.

## Groups, and the two rules that decide what a row means

**The key is `Card#fingerprint`**, the app's existing "same card, any printing" key, the one
`Decks::ArchetypeDetector` matches on: 2 Budew (PRE) plus 2 Budew (ASC) is one group of four copies,
which is what both the rules and the probabilities say. Grouping by printing splits it into two
2-ofs and understates every number about it. A card with no fingerprint falls back to
`"card:#{card.id}"` and therefore forms a group of its own — a bare `group_by(&:fingerprint)` would
merge every unfingerprinted printing into one group, `nil` being a perfectly good Hash key.

**A Basic is `card_type == "Pokémon" AND stage == "Basic"`, never `stage` alone.** Measured on the
development catalogue: 2 196 Pokémon carry `stage = "Basic"` — and so do **50 Basic Energy cards**.
Testing `stage` alone counts a deck's Energy toward the mulligan, which makes the rate wrong in the
reassuring direction, by a lot, on exactly the decks that play the most Energy.

**`Groups` preloads `deck_cards: :card` itself** rather than trusting its caller's `includes`, and
that is a correction rather than a preference: the flat-cost test that was meant to hold its cost
down compared a *warm* association against a *cold* one, and fixing it the obvious way — dropping
the `reload` — would have made both sides warm and hidden the per-card N+1 instead of catching it.
Its cost is a constant four queries whatever the decklist. The consequence for `DecksController#odds`
is recorded in a comment there: the action's own preload became dead weight and was removed, having
been measured at two extra statements, 8 against 6, **both served by the query cache** and therefore
invisible to `SQLCounter`.

**A `force: true` rescrape splits a group, silently, and there is no repair tool.** `compute_fingerprint`
recomputes from the card's own text, so a rescrape can move one printing's fingerprint out from under
the group it shared. Measured by moving a printing's fingerprint with `update_column` between two
reads of one deck: *3 groups, "Budew" 4 copies, opening 44.35 %* became *4 groups, "Budew" twice at 2
copies each, opening 24.59 % each*. The page writes nothing, so nothing is corrupted — it simply
answers a different, wrong question until the printings agree again, with no notice.
`bin/rails card_labels:resync_fingerprints` repairs label assignments and does **not** help here,
because this page keys on the live fingerprint rather than on a stored copy of it. That is the same
trade `Decks::ArchetypeDetector` makes and for the same reason: nothing to drift out of date, at the
price of nothing to repair.

## The page ships curves, and JavaScript only indexes into them

`Report` precomputes, per group, the whole curve over every reachable scenario — 54 points on a
60-card deck — and each cell ships it in a `data-curve` attribute. `deck_odds_controller.js` picks
an index out of it and formats the number. **There is no arithmetic in JavaScript**, and the reason
is not taste: this repository has no JS test infrastructure, so a second implementation of the
conditional hypergeometric would be held down by nothing whatsoever.

Because `d` and `p` enter the formulas through their sum, **one curve indexed by `seen` serves all
three steppers**. The prize columns are the exception and carry a seven-point curve indexed by
prizes taken alone, because "is every copy still sitting in the prizes" is a question about the
prize block itself rather than about accessibility. That is also the sentence a merged control could
not say: a one-of is unreachable 10.00 % of the time at no prizes taken and 0.00 % at six.

**The rounding happens once**, in `Report.percent`, in percent. Ruby then prints the stored number
with `format("%.2f")` and JavaScript with `toFixed(2)`, so the two can never disagree about a digit
— which they could if the curve shipped as a fraction and each side rounded for itself.

**The server-rendered scenario is not decoration.** The cells and the summary render at
`Result#default_seen` before Stimulus starts, and that is all a reader with no JavaScript ever sees.
Nothing asserted it until the attack on the plan said so: the system test only looks after
`connect()` has rewritten every cell, and the component test read attributes rather than text.

**What it costs, measured on a realistic 60-card list** — 25 groups, so 1 350 evaluations over 54
points — in the test container on the development machine (native arm64, not emulated): the
evaluations alone are 23.5 ms warm and 29.7 ms against a freshly built `Deal`, `Report.call` end to
end is 30.5 ms, and the page ships **9 671 bytes** of `data-curve` inside a 51 KB body. Binomials are
memoised for the life of one `Deal`, which is the life of one report. Those figures are the ones to
weigh before adding a *third* scenario axis: each axis multiplies the curve, and the cost is already
tens of milliseconds rather than units. An earlier note in `report.rb` claimed 5 ms and was out by a
factor of five.

## The combination calculator is the one control that goes to the server

Its whole input is a string in the query, which a reader can type, so **every malformed shape fails
closed into a sentence**: a key the deck does not hold, a card named in two buckets, an empty
bucket, a param that is not a `String`, more than `MAX_BUCKETS` buckets. The picker greying out a
card already used elsewhere is a convenience, not a guarantee — **disjointness is what lets
`Deal#all_buckets` add bucket sizes rather than compute a set union**, so a param that broke it would
not raise, it would produce a *wrong number*, which is worse. That was confirmed by sabotage: with
the uniqueness check removed the page printed 28.12 % for a card named in two groups.

**`MAX_BUCKETS` is 4**, which is 2⁴ = 16 inclusion–exclusion terms. The separators are `"."` between
cards and `"|"` between buckets, neither of which can occur in a group key — a key is 16 hex
characters (`Digest::SHA256.hexdigest(…)[0, 16]`) or `"card:<id>"`.

**The assignment lives in the frame, not in the Stimulus controller.** Every pick, drop and new
group navigates the Turbo Frame and the response re-renders the chips *and* the answer together, so
the bucket cap, the disjointness rule and the group names live in one place instead of two. The
picker's *list* still ships with the page and filters client-side — the deck has about 25 groups and
looking at them should need no request. The cost is one request per pick, about five for a realistic
combination, inside the action's 30/min ration. This is a deliberate departure from the spec, which
composed buckets client-side and asked the server only for the curve.

Two details that cost time to find and would cost it again: **`ComboFrame` must
`include Phlex::Rails::Helpers::TurboFrameTag` by hand** — `ApplicationComponent` does not — and the
`deck-combo` controller re-greys the picker on **`stateTargetConnected`, not
`frameTargetConnected`**, because Turbo replaces a frame's *children* and leaves the `turbo-frame`
element itself in place. A third: "New group" opens the picker on a group that does not exist yet
rather than navigating to an empty one, because `Combo` refuses an empty bucket and the
serialisation drops it — navigating would have produced an identical `src`, no navigation, and no
group to fill.

## What the page refuses to say

Five states, and the order of the first two is load-bearing:

| State | What it says |
|---|---|
| A deck of 0 cards, or fewer than 7 | it holds too few cards to deal a hand — **tested before** the Basics, because a deck of nothing satisfies both and "no Basic Pokémon" sends a reader who just clicked *New deck* looking for a card type |
| No Basic Pokémon | it cannot start a game, so there is nothing to compute |
| `N ≠ 60` | the numbers are computed against the **real** `N`, with a notice naming the gap — a deck under construction is when this page is most useful, so this is the normal state, not an edge case |
| `N < 13` | a hand is dealt and no prizes; the prize section is absent, not zeroed |
| Partial role curation | the count of copies carrying no role label yet, Basic Energy included, because that is literally true and the alternative is inventing a rule for which cards *could* carry one |

The four limits of the model are printed on the page itself, in `MethodNote`: it knows nothing about
draw Supporters, about mulligan redraws changing the deck, about an opponent's disruption, or about
what a player would keep.

## Public surface

`GET /decks/:id/odds` rides out of `authenticate :user` with the rest of `resources :decks` and
gates itself through `PubliclyReachable` — see `docs/architecture/public-surface.md`. It is the
app's **third unscoped deck lookup**, after `#show` and `#export`, and `authorize` is the very next
line for that reason: nothing else loads until it has run.

It reuses **`DeckPolicy#show?`** and deliberately grows no `odds?` of its own. This page is a pure
function of the decklist, which `#show` already renders in full, so a separate rule could only ever
come to disagree with itself. `#stats` stays owner-only and is untouched.

`ODDS_RATE_LIMIT_TO` is **30/min**, anonymous only, under its own `name: "decks-odds"` — matching
the export and for the same reason. `#show` is exempt because it has no live control behind it; the
scenario steppers are client-side and emit nothing, but the combination calculator *is* a live
control and it navigates a frame back to this action. The `name:` is not cosmetic: sharing
`"decks-export"` merges the two budgets, and losing the `unless: -> { user_signed_in? }` throttles
the deck's own signed-in owner. Both were invisible until tested, the test environment's cache being
`:null_store`, which makes `rate_limit` a no-op everywhere else in the suite.

The action assigns **no `assign_og_payload`**: `Og::DeckPayload` walks the archetype and the pool,
neither of which this action loads, and the layout already falls back to the committed default
banner.

**No navbar entry.** The row does not shrink to fit — nine entries were 661 px off the document at
769 px before they were grouped (`docs/architecture/frontend.md`) — and this page belongs to one
deck, which is where it is linked from.

## Rejected

- **A Monte Carlo simulator.** Would let draw Supporters be modelled properly, at the cost of
  sampling error on every number and a far larger feature. The closed form is exact, and the honest
  caveat in `MethodNote` is cheaper than an inexact engine.
- **Computing in JavaScript.** Instant combinations, and a second implementation of the mathematics
  in a repository with no JS tests.
- **Everything server-rendered, the steppers included.** Consistent with `/archetypes`, but a
  network round trip per notch kills the exploration the page exists for. Precomputed curves get
  both.
- **A naive `7 of 60` table.** Simpler, and wrong by up to 9.41 points on Basic Pokémon.
- **Grouping rows by printing.** Splits 2 Iono + 2 Iono into two 2-ofs.
- **A segmented `— / A / B / C` control per row.** Makes disjointness structural, but means scanning
  25 rows to assign 4, and gives no name to what a bucket means.
