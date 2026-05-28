class Decks::CardmarketExporter < ApplicationService
  TERA_ABILITY = "Tera".freeze

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
    case card.card_type
    when "Pokémon" then pokemon_name(card)
    when "Energy"  then energy_name(card)
    when "Trainer" then trainer_name(card)
    else card.name
    end
  end

  def pokemon_name(card)
    abilities = card.abilities.map(&:name).reject { |n| n == TERA_ABILITY }
    [ card.name, *abilities, *card.attacks.map(&:name) ].compact_blank.join(" ")
  end

  def energy_name(card)
    return "Basic #{card.name}" if card.subtype == "Basic Energy"

    card.name
  end

  def trainer_name(card)
    variant = cardmarket_variant(card)
    variant ? "#{card.name} #{variant}" : card.name
  end

  # Extract the Cardmarket variant tag from the product URL slug.
  # Cardmarket disambiguates reprints with a suffix like "V1" or a character name.
  # Example: ".../Bosss-Orders-V1-PAL172" with name "Boss's Orders" -> "V1"
  def cardmarket_variant(card)
    return nil if card.cardmarket_url.blank?

    slug = File.basename(URI.parse(card.cardmarket_url).path)
    slug = slug.sub(/-[A-Z]+\d+\z/, "")
    name_slug = slugify(card.name)
    return nil unless slug.start_with?(name_slug)

    suffix = slug.delete_prefix(name_slug).delete_prefix("-")
    suffix.presence&.tr("-", " ")
  end

  def slugify(name)
    I18n.transliterate(name).gsub(/[^A-Za-z0-9\s]/, "").strip.gsub(/\s+/, "-")
  end
end
