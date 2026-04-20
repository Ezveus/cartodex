class Decks::Duplicator < ApplicationService
  NAME_PREFIX = "Copy of "

  def initialize(deck)
    @deck = deck
  end

  def call
    ActiveRecord::Base.transaction do
      new_deck = @deck.user.decks.create!(
        name: "#{NAME_PREFIX}#{@deck.name}",
        description: @deck.description
      )

      @deck.deck_cards.find_each do |dc|
        new_deck.deck_cards.create!(card_id: dc.card_id, quantity: dc.quantity)
      end

      new_deck
    end
  end
end
