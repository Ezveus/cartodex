# Plan — card page usage by archetype, pool and tournament

Spec: `docs/superpowers/specs/2026-11-25-card-archetype-usage-design.md`.

## Frozen contract

```ruby
module Cards
  class ArchetypeUsage < ApplicationService
    VENUES = %w[all paper online].freeze
    OUTSIDE_STANDARD_LABEL = "Outside Standard".freeze

    # lists_count, playing_count: Integers. pct: Float, (100.0 * playing / lists).round(1).
    # min_copies / max_copies / modes: over the playing lists; nil / nil / [] when none plays it.
    Usage = Struct.new(:lists_count, :playing_count, :pct, :min_copies, :max_copies, :modes, keyword_init: true)
    #   #played?  #single_quantity?  #tied_mode?   (CopiesText reads the last two plus min/max/modes)

    TournamentNode = Struct.new(:tournament_id, :label, :usage, :analysis_params, keyword_init: true)
    PoolNode = Struct.new(:pool_id, :label, :usage, :tournaments, :unplayed_tournaments_count,
                          :analysis_params, keyword_init: true)   # pool_id nil => Outside Standard, analysis_params nil
    ArchetypeNode = Struct.new(:archetype, :usage, :pools, :analysis_params, keyword_init: true)
    Option = Struct.new(:value, :label, keyword_init: true)

    Result = Struct.new(:venue, :venue_options, :venue_selectable, :archetypes, keyword_init: true)
    #   #venue_selectable?  #any?   venue: :all/:paper/:online

    def initialize(card:, venue_param: nil)
  end
end
```

`analysis_params` is a Hash with Symbol keys and String values: `{ pool: "all" }`,
`{ pool: "12" }`, `{ pool: "12", tournament: "345" }`, plus `venue: "paper"|"online"` unless `:all`.

## Lanes

**Server lane** — `app/services/cards/archetype_usage.rb`, `test/services/cards/archetype_usage_test.rb`,
`app/controllers/cards_controller.rb`, `test/controllers/cards_controller_test.rb`,
`test/controllers/cards_rate_limit_test.rb`.

**View lane** — `app/views/components/cards/usage_section.rb`, `app/views/components/cards/show_view.rb`,
`app/views/cards/show.html.erb`, `app/assets/stylesheets/application.css`,
`test/components/cards/usage_section_test.rb`, `test/system/card_usage_test.rb`.

Small enough for one implementer: the view depends on the service's real output in the system test,
so both lanes are done in sequence by me, TDD, red then green.

## Tests

The first list below was mine; `ship-plan-adversary` then mutated the service against the parity
test alone and found twelve decisions it could not see (exact link Hashes, pool nodes silently
skipped by the walk, venue leakage, ordering, the deck counted per standing, fingerprint against
name, the unfingerprinted key, the standing's archetype against the deck's, the 3-query premise,
the visitor guard in `card_allocation_test.rb`, the rate-limit name, the 0 % copies text). Each has
a test in `test/services/cards/archetype_usage_test.rb`, `test/components/cards/usage_section_test.rb`,
`test/controllers/card_usage_test.rb` or `test/controllers/cards_rate_limit_test.rb`.

1. Parity: for fixtures building two archetypes, two pools, a non-Standard event, two venues, a
   reprint pair and an unfingerprinted card, every node's usage equals
   `CardStats.call(standings: MetagameScope.call(archetype:, pool_param:, venue_param:, tournament_param:).listed_standings)`'s
   entry for the card's key — iterating every node the service returns.
2. A deck holding two printings of the card counts once, copies summed.
3. Unfingerprinted card: only its own id; another unfingerprinted card of the same name is not counted.
4. A list-less standing is excluded from denominators.
5. Pool at 0 % listed; unplayed tournaments counted, not listed.
6. Venue clamp and `venue_selectable?` both ways; junk venue params (Array, Hash, "x").
7. Ordering: archetypes by playing count then name; pools by recency then id; tournaments newest
   first then id — each with fixtures where the obvious wrong order differs.
8. Query count flat (5: rows, archetypes, pools and their two bounds) across a small and a larger card, outside the query cache.
9. Controller: visitor and member get the section; `?venue[]=x` does not 500; rate limit 120 for
   visitors under its own name, members exempt.
10. Component: links carry exactly the analysis params; Outside Standard has no link; empty state.
11. System: the tree opens, the venue select submits, the figure equals the analysis page's for the
    linked node; at both sweep widths, no horizontal overflow.
