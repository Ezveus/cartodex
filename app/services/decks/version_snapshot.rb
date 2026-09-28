module Decks
  # Records a deck's live list and classification as a new DeckVersion. Raises rather than
  # answering an unsaved version, so a caller inside a transaction rolls the whole write back —
  # which is what Decks::ResultRecorder and Tournaments::EntriesController rely on.
  class VersionSnapshot < ApplicationService
    def initialize(deck, effective_at: Time.current)
      @deck = deck
      @effective_at = effective_at
    end

    def call
      version = DeckVersion.new(
        deck: @deck, effective_at: @effective_at, format: @deck.format,
        standard_pool_id: @deck.standard_pool_id, other_format_name: @deck.other_format_name
      )
      @deck.deck_cards.where("quantity > 0").pluck(:card_id, :quantity).each do |card_id, quantity|
        version.deck_version_cards.build(card_id: card_id, quantity: quantity)
      end

      serialized_transaction { version.save! }
      # A loaded association would otherwise go on answering latest_version without this one.
      @deck.deck_versions.reset
      version
    end
  end
end
