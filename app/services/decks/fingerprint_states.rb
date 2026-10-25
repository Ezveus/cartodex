module Decks
  # The deck page's rows, one per card (Card#fingerprint_key) rather than one per printing, each
  # carrying every printing of that card the page can act on and the numbers its controls need.
  #
  # Every number a control shows or is bounded by is computed here, server-side, so that the
  # browser applies an answer and computes nothing: a bound kept by the browser is what left the
  # real + refusing silently after a quantity + until a reload.
  #
  # `call` is the owner's page; `deck_only` is the public page, which may read neither the
  # collection nor `card_sets` and so must run no query at all.
  class FingerprintStates
    # One printing of a card, from the point of view of one deck.
    #
    # group: :deck (in the deck), :owned (not in the deck, at least one copy owned), :other.
    # max_owned is the real +'s bound; move_from is ⇄'s source (see .build); can_add_to_collection decides
    # whether "+ add to my collection and use it here" is offered — exactly when
    # Decks::CollectionCopyAdder would accept it. One more copy is free for this deck iff the
    # printing's committed reals do not exceed what is owned; beside "no free copy"
    # (available <= owned_copies) that leaves committed == owned, so an over-allocated printing is
    # refused here as the adder refuses it.
    PrintingState = Struct.new(:card, :deck_card, :group, :quantity, :owned_copies, :proxies,
                               :owned, :available, :max_owned, :over_allocated, :move_from,
                               :can_add_to_collection, keyword_init: true) do
      def as_json(*)
        {
          card_id: card.id, set_name: card.set_name, set_number: card.set_number, group: group.to_s,
          quantity: quantity, owned_copies: owned_copies, proxies: proxies, owned: owned,
          available: available, max_owned: max_owned, over_allocated: over_allocated,
          move_from_card_id: move_from&.id, can_add_to_collection: can_add_to_collection
        }
      end
    end

    State = Struct.new(:key, :name, :card_type, :subtype, :display_card, :printings, keyword_init: true) do
      def in_deck = printings.select { |printing| printing.group == :deck }

      def quantity = in_deck.sum(&:quantity)
      def owned_copies = in_deck.sum(&:owned_copies)
      def proxies = in_deck.sum(&:proxies)

      def over_allocated? = in_deck.any?(&:over_allocated)
      def single? = in_deck.size == 1

      # On a deck_only state every printing is in the deck, so this means "several printings in
      # the deck" there and "the catalogue holds another printing" on the owner's.
      def reprinted? = printings.size > 1

      def as_json(*)
        {
          key: key, name: name, quantity: quantity, owned_copies: owned_copies, proxies: proxies,
          printings: printings.map(&:as_json)
        }
      end
    end

    GROUP_ORDER = %i[deck owned other].freeze

    # Hash{ fingerprint_key => State }, one per card the deck holds. The deck's `deck_cards` (with
    # `card`) are read as loaded. Two reads besides: every printing of the deck's fingerprints, then
    # Availability's grouped three over all of them — whether or not the deck is physical, since
    # the :owned group needs `owned` on any deck.
    def self.call(user:, deck:)
      deck_cards = deck.deck_cards.to_a
      return {} if deck_cards.empty?

      catalogue = printings_by_key(deck_cards)
      availability = Allocations::Availability.for_cards(
        user: user, cards: catalogue.values.flatten, excluding_deck: deck
      )
      rows_by_card = deck_cards.index_by(&:card_id)

      catalogue.transform_values do |printings|
        states = printings.map do |card|
          owner_printing(card, rows_by_card[card.id], availability.fetch(card.id), physical: deck.physical?)
        end
        build(states.sort_by.with_index { |state, index| [ GROUP_ORDER.index(state.group), index ] },
              physical: deck.physical?)
      end
    end

    # The same shape from the deck's own rows alone, for the public page: no query, no collection
    # data. The printings are the in-deck ones, ordered by what the rows carry — set code, then
    # number — since the catalogue order needs `card_sets`.
    def self.deck_only(deck_cards)
      deck_cards.group_by { |deck_card| deck_card.card.fingerprint_key }.transform_values do |rows|
        ordered = rows.sort_by { |row| [ row.card.set_name.to_s, SetGroups.number_key(row.card.set_number) ] }
        build(ordered.map { |row| public_printing(row) }, with_move_from: false)
      end
    end

    # Every printing of each fingerprint the deck holds, in Cards::Printings' order, keyed on the
    # fingerprint key. A card with no fingerprint has no equivalent and is its own only printing.
    def self.printings_by_key(deck_cards)
      cards = deck_cards.map(&:card)
      fingerprints = cards.filter_map { |card| card.fingerprint.presence }.uniq
      reprints = if fingerprints.empty?
        {}
      else
        Card.where(fingerprint: fingerprints)
            .left_joins(:card_set)
            .order(Arel.sql("card_sets.release_date IS NULL, card_sets.release_date DESC"))
            .order(:set_name, :set_number)
            .group_by(&:fingerprint)
      end

      cards.each_with_object({}) do |card, result|
        result[card.fingerprint_key] ||= reprints.fetch(card.fingerprint, [ card ])
      end
    end
    private_class_method :printings_by_key

    def self.owner_printing(card, deck_card, counts, physical:)
      quantity = deck_card&.quantity.to_i
      owned_copies = deck_card&.owned_copies.to_i
      group = if deck_card then :deck elsif counts.owned.positive? then :owned else :other end
      over_allocated = physical && counts.committed > counts.owned

      PrintingState.new(
        card: card, deck_card: deck_card, group: group,
        quantity: quantity, owned_copies: owned_copies, proxies: quantity - owned_copies,
        owned: counts.owned, available: counts.available,
        max_owned: physical ? [ quantity, counts.available ].min : 0,
        over_allocated: over_allocated,
        can_add_to_collection: physical && !over_allocated && quantity > owned_copies &&
          counts.available <= owned_copies
      )
    end
    private_class_method :owner_printing

    def self.public_printing(deck_card)
      PrintingState.new(
        card: deck_card.card, deck_card: deck_card, group: :deck,
        quantity: deck_card.quantity, owned_copies: deck_card.owned_copies.to_i,
        proxies: deck_card.quantity - deck_card.owned_copies.to_i,
        owned: 0, available: 0, max_owned: 0, over_allocated: false, can_add_to_collection: false
      )
    end
    private_class_method :public_printing

    # The row's display card is the in-deck printing with the most copies. ⇄'s source is the other
    # in-deck printing with the most proxies — a proxy moved is a card nobody owns changing its
    # printed set, where a real one moved would leave a physical card unaccounted for — then the
    # most copies. Both break the last tie on the first in printing order (newest set first). A
    # non-physical deck backs nothing, so its proxies are not compared at all and ⇄ goes by copies.
    def self.build(printings, with_move_from: true, physical: false)
      in_deck = printings.select { |printing| printing.group == :deck }
      if with_move_from
        printings.each do |printing|
          printing.move_from = move_source(in_deck.reject { |source| source.equal?(printing) }, physical:)&.card
        end
      end

      display = most_copies(in_deck).card
      State.new(key: display.fingerprint_key, name: display.name, card_type: display.card_type,
                subtype: display.subtype, display_card: display, printings: printings)
    end
    private_class_method :build

    # The index breaks the tie explicitly rather than trusting `max_by` to keep the first of equal
    # maxima, which Ruby does not document.
    def self.most_copies(printings)
      printings.each_with_index.max_by { |printing, index| [ printing.quantity, -index ] }&.first
    end
    private_class_method :most_copies

    def self.move_source(printings, physical:)
      printings.each_with_index.max_by do |printing, index|
        [ physical ? printing.proxies : 0, printing.quantity, -index ]
      end&.first
    end
    private_class_method :move_source
  end
end
