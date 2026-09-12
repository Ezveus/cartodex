module Decks
  module Odds
    # Everything /decks/:id/odds prints, computed once per request.
    #
    # The page is reactive without being a second implementation of the model: every cell the
    # scenario controls move carries its *whole curve*, precomputed here over every reachable
    # scenario, and the Stimulus controller only picks an index out of it. `d` and `p` enter Deal's
    # formulas through their sum alone, so one curve indexed by `a_rest` serves all three steppers;
    # the prize columns are the exception, being a question about the prize block itself, and carry
    # a seven-point curve indexed by prizes taken.
    #
    # Measured: 1 350 evaluations — 25 groups over 54 points — take about 5 ms, which is less than
    # the page render around them.
    class Report < ApplicationService
      # What the scenario opens on: one turn taken, no effect draws, no prizes collected.
      DEFAULT_TURN = 1

      # A legal deck. Anything else is not an edge case to tolerate but the normal state of a deck
      # under construction, which is when this page is most useful — so the numbers are computed
      # against the real N and a notice names the gap.
      REFERENCE_DECK_SIZE = 60

      # The prize panel exists for its *ordering*, and the per-card table below it already carries
      # every group's prize columns. Uncapped it would restate a 25-row table in a different order.
      PRIZE_PANEL_SIZE = 5

      # The single rounding in the whole feature, and it happens once, here, in percent. Both Ruby
      # and JavaScript then format the same stored number the same way — `format("%.2f", value)` and
      # `value.toFixed(2)` — so the two can never disagree about a digit, which they could if the
      # curve shipped as a fraction and each side rounded for itself.
      def self.percent(rational) = (rational * 100).to_f.round(2)

      CardRow = Struct.new(:key, :name, :card, :copies, :opening, :accessible_curve,
                           :at_least_one_prized, :all_prized_curve, keyword_init: true)

      RoleRow = Struct.new(:slug, :name, :copies, :opening, :accessible_curve, keyword_init: true)

      Result = Struct.new(:deck, :deal, :groups, :card_rows, :role_rows, :prize_rows,
                          keyword_init: true) do
        def deck_size = groups.deck_size
        def basics = groups.basics
        def uncurated_copies = groups.uncurated_copies
        def entries_by_key = groups.entries_by_key

        def hand_size = deal.hand_size
        def prize_count = deal.prize_count
        def max_draws = deal.max_draws
        def max_seen = deal.max_seen
        def playable? = deal.playable?
        def prizes? = deal.prize_count.positive?
        def reference_size? = deck_size == REFERENCE_DECK_SIZE

        def mulligan_rate_percent = Report.percent(deal.mulligan_rate)
        def mean_mulligans = deal.mean_mulligans.to_f.round(3)

        # The index every reactive cell opens on. Clamped, because a deck of seven cards has a
        # zero-length draw pile and no first turn to take.
        def default_seen = [ DEFAULT_TURN, max_seen ].min
      end

      def initialize(deck)
        @deck = deck
      end

      def call
        return Result.new(**empty) unless deal.playable?

        rows = card_rows

        Result.new(
          deck: @deck, deal: deal, groups: groups,
          card_rows: rows,
          role_rows: role_rows,
          prize_rows: prize_rows(rows)
        )
      end

      private

      def groups = @groups ||= Groups.call(@deck)

      def deal
        @deal ||= Deal.new(deck_size: groups.deck_size, basics: groups.basics, prize_count: prize_count)
      end

      # A deck under construction can hold fewer cards than a hand plus six prizes, and there is no
      # honest prize section for it. Passing 0 rather than refusing the whole page keeps the deal
      # itself answerable down to seven cards.
      def prize_count
        groups.deck_size >= Deal::HAND_SIZE + Deal::PRIZE_COUNT ? Deal::PRIZE_COUNT : 0
      end

      def prizes? = prize_count.positive?

      def empty
        { deck: @deck, deal: deal, groups: groups, card_rows: [], role_rows: [], prize_rows: [] }
      end

      def card_rows
        groups.entries.map do |entry|
          curve = accessible_curve(entry.copies, entry.non_basic_copies)

          CardRow.new(
            key: entry.key, name: entry.name, card: entry.card, copies: entry.copies,
            opening: curve.first,
            accessible_curve: curve,
            at_least_one_prized: self.class.percent(deal.at_least_one_prized(copies: entry.copies)),
            all_prized_curve: all_prized_curve(entry.copies)
          )
        end
      end

      # One row per role present in the deck, counting *copies*. A card carrying two roles is counted
      # under both — the sections overlap and do not add up to a list, which is what the panel's own
      # sentence says, exactly as Archetypes::CardReport's does.
      def role_rows
        groups.roles.map do |label|
          entries = groups.entries.select { |entry| entry.roles.include?(label) }
          copies = entries.sum(&:copies)
          curve = accessible_curve(copies, entries.sum(&:non_basic_copies))

          RoleRow.new(slug: label.slug, name: label.name, copies: copies,
                      opening: curve.first, accessible_curve: curve)
        end
      end

      def prize_rows(rows)
        return [] unless prizes?

        rows.sort_by { |row| [ -row.all_prized_curve.first, -row.at_least_one_prized, row.name ] }
            .first(PRIZE_PANEL_SIZE)
      end

      def accessible_curve(copies, non_basic_copies)
        (0..deal.max_seen).map do |seen|
          self.class.percent(
            deal.accessible(copies: copies, non_basic_copies: non_basic_copies, seen: seen)
          )
        end
      end

      def all_prized_curve(copies)
        (0..deal.prize_count).map do |taken|
          self.class.percent(deal.all_prized(copies: copies, taken: taken))
        end
      end
    end
  end
end
