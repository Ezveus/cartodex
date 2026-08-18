module Collections
  # Owned printings physically interchangeable with the given card — i.e. sharing
  # its Card#fingerprint. Purely advisory: allocation is unaffected. One entry per
  # printing, reporting owned (summed across the printing's variants) and
  # available. Includes fully-committed printings (available: 0). Unordered.
  class OwnedEquivalents < ApplicationService
    def initialize(user:, card:, excluding_card: false)
      @user = user
      @card = card
      @excluding_card = excluding_card
    end

    def call
      return [] if @card.fingerprint.blank?

      equivalent_ids = Card.where(fingerprint: @card.fingerprint).select(:id)
      rows = @user.collections.with_cards.where(card_id: equivalent_ids).includes(:card).to_a

      # Grouped, because one printing may now be owned in several variants and
      # the entry describes the printing: language and finish distinguish copies
      # for owning and buying, never for interchangeability, which is what this
      # service is about.
      rows_by_card = rows.group_by(&:card)

      # Batched: this was one Availability call per printing, so the cost grew
      # with however many printings of the card the user owns.
      availability = Allocations::Availability.for_cards(user: @user, cards: rows_by_card.keys)

      rows_by_card.filter_map do |card, owned_rows|
        next if @excluding_card && card.id == @card.id

        {
          card_id: card.id,
          set_name: card.set_name,
          set_number: card.set_number,
          rarity: card.rarity,
          owned: owned_rows.sum(&:quantity),
          available: availability[card.id].available
        }
      end
    end
  end
end
