module Decks
  module Odds
    # A deck's cards, folded into the groups every probability on /decks/:id/odds is computed over.
    #
    # The key is Card#fingerprint — the app's existing "same card, any printing" key, the one
    # Decks::ArchetypeDetector matches on — because 2 Iono (PAL) plus 2 Iono (PAF) is one group of
    # four copies, which is what both the rules and the probabilities say. Grouping by printing
    # splits it into two 2-ofs and understates every number about it.
    class Groups < ApplicationService
      # The fallback key for a card with no fingerprint. Only a write that bypasses callbacks can
      # produce one (compute_fingerprint is a before_save), and such a card forms a group of its own
      # rather than merging with every other unfingerprinted card — which a bare
      # `group_by(&:fingerprint)` would do, nil being a perfectly good Hash key.
      def self.key_for(card) = card.fingerprint.presence || "card:#{card.id}"

      Entry = Struct.new(:key, :name, :card, :copies, :basic, :card_type, :subtype, :roles,
                         keyword_init: true) do
        def basic? = basic

        # The only place the overlap between a group and the deck's Basics reaches Deal. A
        # fingerprint group is homogeneous in `stage`, so this is either 0 or the whole group.
        def non_basic_copies = basic? ? 0 : copies
      end

      Result = Struct.new(:deck_size, :basics, :entries, keyword_init: true) do
        def entries_by_key = @entries_by_key ||= entries.index_by(&:key)

        # Every role any card in the deck carries, in the order CardLabel.roles would return them.
        def roles
          @roles ||= entries.flat_map(&:roles).uniq.sort_by { |label| [ label.position, label.slug ] }
        end

        # Copies — not groups — of cards carrying no role label at all. The role panel prints this,
        # because a `search` count of 4 in a deck playing 12 uncurated searchers is a lie by
        # omission. Basic Energy is included and that is deliberate: it is literally true, and the
        # alternative is inventing a rule for which cards *could* carry a role, which the label
        # store does not have.
        def uncurated_copies = entries.reject { |entry| entry.roles.any? }.sum(&:copies)
      end

      def initialize(deck)
        @deck = deck
      end

      def call
        entries = grouped.map { |key, deck_cards| entry_for(key, deck_cards) }
                         .sort_by { |entry| [ -entry.copies, entry.name ] }

        Result.new(
          deck_size: entries.sum(&:copies),
          basics: entries.select(&:basic?).sum(&:copies),
          entries: entries
        )
      end

      private

      # The `includes(:card)` is this service's own and not its caller's. Every group reads its
      # cards' fingerprint, name, stage and type, so a deck handed over cold costs one query per
      # printing without it — measured 1 against 8 on a six-card list — and depending on an
      # `includes` somewhere up the stack makes this service's cost a property of whoever happens
      # to call it. Memoised because `roles_by_key` asks for the keys again.
      def grouped
        @grouped ||= @deck.deck_cards.includes(:card)
                          .group_by { |deck_card| self.class.key_for(deck_card.card) }
      end

      def entry_for(key, deck_cards)
        # The printing that names the group. Lowest set number of the lowest set code, so the same
        # group is labelled identically whatever order the decklist happened to be typed in.
        card = deck_cards.map(&:card).min_by { |c| [ c.set_name.to_s, c.set_number.to_s ] }

        Entry.new(
          key: key,
          name: card.name,
          card: card,
          copies: deck_cards.sum(&:quantity),
          basic: basic?(card),
          card_type: card.card_type,
          subtype: card.subtype,
          roles: roles_by_key.fetch(key, [])
        )
      end

      # `card_type` as well as `stage`, never `stage` alone: 50 Basic Energy cards in the
      # development catalogue carry stage = "Basic", and counting them toward the mulligan makes the
      # mulligan rate wrong in the reassuring direction on exactly the decks that play the most
      # Energy.
      def basic?(card)
        card.card_type == "Pokémon" && card.stage == "Basic"
      end

      # fingerprint -> the role labels on that card, in one query for the whole deck.
      #
      # `eager_load`, not `includes`: the scope filters on card_labels.family, so the join has to be
      # there. Unconditional — no early return on an empty deck — so that the page's query count
      # does not depend on whether the deck happens to hold a card, which is what makes the
      # flat-cost test in DecksControllerTest measure an N+1 rather than a branch change.
      def roles_by_key
        @roles_by_key ||= CardLabelAssignment
          .active
          .eager_load(:card_label)
          .where(fingerprint: grouped.keys, card_labels: { family: "role" })
          .group_by(&:fingerprint)
          .transform_values do |assignments|
            assignments.map(&:card_label).sort_by { |label| [ label.position, label.slug ] }
          end
      end
    end
  end
end
