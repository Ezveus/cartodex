module Collections
  # Owned printings physically interchangeable with the given card — i.e. sharing
  # its Card#fingerprint. Purely advisory: allocation is unaffected. Each entry
  # reports per-printing owned/available. Includes fully-committed printings
  # (available: 0). Unordered.
  class OwnedEquivalents < ApplicationService
    def initialize(user:, card:, excluding_card: false)
      @user = user
      @card = card
      @excluding_card = excluding_card
    end

    def call
      return [] if @card.fingerprint.blank?

      equivalent_ids = Card.where(fingerprint: @card.fingerprint).select(:id)
      collections = @user.collections.with_cards.where(card_id: equivalent_ids).includes(:card)

      collections.filter_map do |collection|
        next if @excluding_card && collection.card_id == @card.id

        available = Allocations::Availability.call(user: @user, card: collection.card).available
        {
          card_id: collection.card_id,
          set_name: collection.card.set_name,
          set_number: collection.card.set_number,
          rarity: collection.card.rarity,
          owned: collection.quantity,
          available: available
        }
      end
    end
  end
end
