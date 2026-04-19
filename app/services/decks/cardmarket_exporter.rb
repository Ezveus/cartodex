class Decks::CardmarketExporter < ApplicationService
  def initialize(deck)
    @deck = deck
  end

  def call
    deck_cards = @deck.deck_cards.includes(card: [ :attacks, :abilities ]).order("cards.name")
    deck_cards.map { |dc| card_line(dc) }.join("\n") + "\n"
  end

  private

  def card_line(dc)
    prefix = dc.quantity > 1 ? "#{dc.quantity}x " : ""
    "#{prefix}#{card_name(dc.card)}".squish
  end

  def card_name(card)
    return card.name unless card.card_type == "Pokémon"

    parts = [ card.name, *card.abilities.map(&:name), *card.attacks.map(&:name) ]
    parts.compact_blank.join(" ")
  end
end
