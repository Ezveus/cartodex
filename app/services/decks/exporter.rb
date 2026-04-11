class Decks::Exporter < ApplicationService
  ENERGY_SYMBOL_TO_CODE = {
    "Grass" => "G", "Fire" => "R", "Water" => "W", "Lightning" => "L",
    "Fighting" => "F", "Psychic" => "P", "Darkness" => "D", "Metal" => "M",
    "Fairy" => "Y", "Dragon" => "N", "Colorless" => "C"
  }.freeze

  def initialize(deck)
    @deck = deck
  end

  def call
    deck_cards = @deck.deck_cards.includes(:card).order("cards.name")

    pokemon = deck_cards.select { |dc| dc.card.card_type == "Pokémon" }
    trainers = deck_cards.select { |dc| dc.card.card_type == "Trainer" }
    energy = deck_cards.select { |dc| dc.card.card_type == "Energy" }

    lines = []
    lines << "Pokémon: #{pokemon.size}"
    pokemon.each { |dc| lines << card_line(dc) }
    lines << ""
    lines << "Trainer: #{trainers.size}"
    trainers.each { |dc| lines << card_line(dc) }
    lines << ""
    lines << "Energy: #{energy.size}"
    energy.each { |dc| lines << card_line(dc) }
    lines.join("\n") + "\n"
  end

  private

  def card_line(dc)
    card = dc.card
    name = card.card_type == "Energy" ? format_energy_name(card) : card.name
    "#{dc.quantity} #{name} #{card.set_name} #{card.set_number}"
  end

  def format_energy_name(card)
    if card.subtype == "Basic Energy" && card.type_symbol.nil?
      type = card.name.sub(/ Energy$/, "")
      code = ENERGY_SYMBOL_TO_CODE[type]
      code ? "Basic {#{code}} Energy" : card.name
    else
      card.name
    end
  end
end
